# gem5/AXIOM-Vergleich

`make gem5-sweep` führt den **gleichen 1×1×8-INT8-SDP-ReLU-Job** mit beiden
Steuerwegen aus. Der lose Pfad schreibt die NVDLA-CSB-Register per CVA6-MMIO;
der enge Pfad startet denselben Job mit einer CV-X-IF-Instruktion. Beide
Varianten enthalten den echten CVA6, das generierte `nv_small`-NVDLA und
ihren AXI-Crossbar. Gem5/AXIOM stellt hinter dem Crossbar einen
`SimpleMemory`-Speicher mit 10, 50 oder 100 ns Latenz bereit. Ein separater
gem5-RISC-V-Prozess initialisiert die acht Eingabebytes, startet das RTL und
prüft Status und Ausgabebytes. **Dessen Instruktionen werden nicht in den
angegebenen RTL-Zyklen mitgezählt.**

Das lokale AXIOM-Plugin bindet den DUT über seinen AXI-Master an gem5 an.
Der PIO-Port des Plugins dient nur zum Starten und Beobachten des DUT. Die
gemessene Zahl zählt ab Freigabe des RTL-CVA6-Resets bis zu dessen `cpu_done`
(am `ebreak` nach Jobabschluss). `gem5_ticks` in der CSV ist die Laufzeit
des gesamten gem5-Testprozesses und enthält dessen Initialisierung und
Prüfung; es ist **kein** geeigneter Wert für den Kopplungsvergleich.

## Reproduzieren

Voraussetzung ist ein für RISC-V gebautes `gem5.opt` mit AXIOMs
`RTLDmaDevicePlugin`. Die auf diesem Rechner benutzte Binärdatei stammt aus
`/home/julian/Development/axiom/build/RISCV/gem5.opt` und aus demselben
AXIOM-Commit wie `ext/axiom`. Ein eigener Build lässt sich mit AXIOMs
`make gem5` erzeugen; den Pfad dann über `GEM5=` setzen:

```sh
make nvdla-rtl
make gem5-sweep GEM5=/pfad/zu/gem5.opt
```

Einzellauf: `make gem5-loose LATENCY=50ns` oder `make gem5-tight
LATENCY=50ns`. Jeder Lauf muss den Status und die Ausgabebytes prüfen, bevor
`collect.py` eine Messzeile in [results.csv](results.csv) schreibt. Die
ausführlichen gem5-Logs liegen nach dem Lauf unter `build/gem5/runs/`.
`plot.py` erzeugt daraus die Vektorgrafiken [Zyklen](results.svg) und
[Verhältnis](speedup.svg).

## Größere INT8-Faltung

`make tb-conv-loose tb-conv-tight` simuliert die vollständige
CDMA→CSC→CMAC→CACC→SDP-Pipeline mit CVA6 und AXI-RAM in Cocotb. Der
`nv_small`-Referenzfall faltet 13×15×64 Eingangswerte mit 5×3×64×16
Gewichten. Das ergibt 12×14×16 Ausgabewerte und rund 2,58 Millionen
Multiply-Accumulate-Operationen. Eingang und Gewichte stammen aus
`ext/nvdla/verif/tests/trace_tests/nv_small/dc_13x15x64_5x3x64x16_int8_0`;
`tools/gen_conv.py` übernimmt die Daten und Registerwerte, verlegt nur die
DMA-Adressen und erzeugt die lokalen Tabellen für beide DUTs.
Beide Cocotb-Tests prüfen alle 0x1500 Ausgabebytes mit der upstream-CRC32
`0x8c467827`.

`make gem5-conv-sweep` führt denselben Job bei 10, 50 und 100 ns
Speicherlatenz für beide Kopplungen aus. Jeder gem5-Lauf prüft zuerst Status
und CRC32; nur gültige Messungen landen in
[conv_results.csv](conv_results.csv). Die daraus erzeugten Diagramme sind
[RTL-Zyklen](conv_results.svg) und [Loose/Tight-Verhältnis](conv_speedup.svg).
Einzellauf: `make gem5-conv-loose LATENCY=10ns` beziehungsweise
`make gem5-conv-tight LATENCY=10ns`.

Der enge `conv`-Befehl ist hier bewusst ein fester Referenzjob. Er beweist,
dass die CV-X-IF-Steuerung die gesamte NVDLA-Faltungspipeline konfigurieren
und starten kann; er implementiert noch keine frei parametrisierte
Convolution-ISA. Die Daten werden als Firmware-ELF-Segmente in den
gemeinsamen RAM geladen. Gem5 misst die RTL-CVA6-Zyklen bis `ebreak`; der
separate gem5-Prüfprozess zählt nicht zu diesen Zyklen.

Alle sechs Faltungsläufe haben Status- und CRC-Prüfung bestanden:

| Speicherlatenz | Loose (RTL-Zyklen) | Tight (RTL-Zyklen) | Loose/Tight |
| ---: | ---: | ---: | ---: |
| 10 ns | 66429 | 66355 | 1,0011× |
| 50 ns | 96554 | 96417 | 1,0014× |
| 100 ns | 137312 | 133985 | 1,0248× |

Bei dieser Faltung ist der Vorteil des engen Pfads deutlich kleiner als
beim kurzen ReLU-Job: rund 0,11 %, 0,14 % beziehungsweise 2,42 % weniger
RTL-Zyklen. Das sind Einzelmessungen dieses Referenzjobs. Sie zeigen, dass
DMA- und Rechenzeit hier den Steueraufwand weitgehend überdecken; daraus
folgt noch keine Aussage über andere Schichten oder vollständige Netze.

## Beobachtung und Grenzen

| Speicherlatenz | Loose (RTL-Zyklen) | Tight (RTL-Zyklen) | Loose/Tight |
| ---: | ---: | ---: | ---: |
| 10 ns | 1225 | 756 | 1,62× |
| 50 ns | 1945 | 874 | 2,23× |
| 100 ns | 2945 | 1019 | 2,89× |

Das ist **ein einzelner kurzer Job pro Konfiguration**, keine statistische
Performance-Studie und kein Beleg für einen Vorteil bei Convolution oder
vollständigen Netzen. Beim losen Pfad werden viele CSB-Registerzugriffe von
der CPU ausgeführt; deren Kosten steigen mit der gem5-Speicherlatenz. Der
enge Controller sequenziert die Register intern und spart diesen Verkehr.
Für lange Jobs muss sich der Startaufwand erst gegen DMA- und Rechenzeit
behaupten. Cache-Kohärenz und allgemeine NVDLA-Deskriptoren sind weiterhin
nicht implementiert.

Die Antwortkanäle des AXIOM-DMA-Adapters wurden für diesen CVA6-DUT durch
einen Puffer in `dut/{loose,tight}/gem5_top.sv` entkoppelt; ohne ihn konnte
wechselndes `RREADY` einen Read-Beat verlieren. Der Puffer hat eine feste
Tiefe und stoppt bei Überlauf explizit. Er ist für beide hier beschriebenen
Jobs validiert, aber noch kein generischer AXI-Bridge-Fix.
