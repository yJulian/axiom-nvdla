# Geplante NVDLA-ISA für den Tight-Pfad

Status: Architekturentwurf, **keine implementierte ISA**. Implementiert sind
derzeit nur `relu8` und `wait` für einen festen 1×1×8-INT8-SDP-Job in
[`cvxif_sdp.sv`](cvxif_sdp.sv). Die folgenden Namen, Encodings und Deskriptoren
sind ein Vorschlag für die nächste Ausbaustufe und noch nicht ABI-stabil.

## Ziel und Trennlinie

Eine Instruktion soll eine **Operation** anstoßen oder ihren Zustand abfragen,
nicht ein einzelnes NVDLA-CSB-Register beschreiben. Convolution benötigt
Eingabe, Gewichte, Ausgabe, Dimensionen, Strides, Padding, Präzision und
Speicherlayout; diese Parameter passen nicht sinnvoll in zwei GPR-Operanden.
Deshalb übergibt `nd.submit` einen Deskriptor im DMA-sichtbaren Speicher.
CV-X-IF transportiert Steuerung und Resultate, während NVDLA weiterhin AXI
für Tensoren und Gewichte verwendet. Ein neuer AXI-Master des Controllers
muss den Deskriptor lesen; die gegenwärtige CV-X-IF-Anbindung bietet dafür
keinen fertigen Datenpfad.

Der Controller besteht künftig aus Decoder/Commit-Schutz, kleinem
Kontextregistersatz, Deskriptor-Fetcher, Validator, Job-Queue, Scheduler,
CSB-Sequencer und Completion-Tracker. Er erzeugt die vielen NVDLA-Register-
schreibvorgänge intern. Ein Software-Treiber baut Deskriptoren, verwaltet
DMA-Speicher und behandelt Interrupts. Die CV-X-IF-`id`/`hartid`-Zuordnung
und der Commit/Kill-Handshake müssen erhalten bleiben: vor einem gültigen
Commit darf `submit` keine sichtbaren CSB- oder DMA-Nebenwirkungen erzeugen;
pro akzeptierter, nicht gekillter Instruktion gibt es genau ein Resultat.
Das folgt der [CV-X-IF-Spezifikation](https://docs.openhwgroup.org/projects/openhw-group-core-v-xif/en/v1.0.0-rc.1/x_ext.html).

## Kompakter Befehlssatz

Alle neuen Befehle verwenden vorläufig `custom-0` (`opcode=0x0b`).
`funct7=0` bleibt für die heutigen Demo-Befehle reserviert; die Tabelle
reserviert `funct7=1..8` bei `funct3=0`. Die endgültige Kodierung wird erst
nach Prüfung des CVA6-Decoders und eines Assemblertests festgelegt.

| Befehl | `funct7` | Operanden | Ergebnis in `rd` | Zweck |
| --- | ---: | --- | --- | --- |
| `nd.cap` | 1 | keine | Versions-/Capability-Wort | Vor jedem Featuretest abfragen, welche Blöcke und Modi das gebaute NVDLA besitzt. |
| `nd.cfgwr` | 2 | `rs1` Registerindex, `rs2` Wert | Status | Controller-Register ändern; kein roher CSB-Schreibbefehl. |
| `nd.cfgrd` | 3 | `rs1` Registerindex | Registerwert/Fehler | Kontext, Status und Performance-Zähler lesen. |
| `nd.submit` | 4 | `rs1` Deskriptoradresse, `rs2` Abhängigkeits-Handle (0 = keine) | Job-Handle/Fehler | Job validieren und asynchron einreihen. |
| `nd.poll` | 5 | `rs1` Job-Handle | pending/running/done/Fehler | Nicht blockierende Statusabfrage. |
| `nd.wait` | 6 | `rs1` Job-Handle | Abschlussstatus/Fehler | Bis zum Abschluss warten und den Job freigeben. Für Bare-Metal einfach; im OS vorzugsweise Interrupt + `poll`. |
| `nd.cancel` | 7 | `rs1` Job-Handle | Status | Nur **noch nicht gestartete** Jobs entfernen; laufendes NVDLA wird nicht präemptiert. |
| `nd.irqack` | 8 | `rs1` Ereignismaske | Status | Abschluss-/Fehlerereignisse quittieren, falls nicht über `cfgwr(IRQ_ACK)` gelöst. |

`rd` verwendet 64 Bit: nichtnegative Werte sind Handles oder Statusdaten,
negative Werte definierte Fehler (`BAD_DESC`, `UNSUPPORTED`, `BAD_ADDR`,
`QUEUE_FULL`, `TIMEOUT`, `HW_ERROR`). Die genaue Bitbelegung und die
Frage, ob `irqack` ein eigener Befehl bleibt, gehören zur ABI-Festlegung.
`nd.poll` konsumiert den Handle nicht; `nd.wait` liefert das finale Ergebnis
und gibt ihn frei. Das heutige `wait` (`funct7=0, funct3=1`) ist ein
Demo-Befehl ohne Handle und wird nicht stillschweigend umgedeutet.

Ein eigener Befehl pro Convolution-, Pooling- oder Aktivierungsparameter ist
ausdrücklich nicht vorgesehen. Häufige Mini-Operationen wie das vorhandene
`relu8` dürfen als Fast Path bleiben, müssen aber dieselbe Validierung,
Completion-Semantik und Fehlerbehandlung wie `submit` benutzen.

## Controller-Register statt vieler Steuerbefehle

Diese Register liegen **im neuen CV-X-IF-Controller**, nicht im NVDLA-CSB
und zunächst auch nicht im CVA6-CSR-Adressraum. `cfgwr/cfgrd` greifen über
einen kleinen Registerindex darauf zu. Strukturelle Einstellungen werden nur
im Leerlauf geändert; beim `submit` wird der Kontext für den Job eingefroren.
Ein OS-Treiber muss Kontexte pro Prozess sichern/wiederherstellen oder
Jobs verschiedener Prozesse strikt voneinander trennen.

| Register | Zugriff | Geplanter Inhalt |
| --- | --- | --- |
| `VERSION`, `CAP0/1` | RO | ISA-/Deskriptorversion; Blöcke, Präzisionen, Adressbreite, Queue-Tiefe und tatsächlich vorhandene Modi. |
| `CTRL` | RW | Enable, Interruptfreigabe, Pause der Job-Annahme, kontrollierter Reset nur im Leerlauf. |
| `STATUS`, `ERROR` | RO | Queue-Belegung, aktive Job-ID, letztes Fehlerstadium und NVDLA-Status. |
| `IRQ_STATUS`, `IRQ_MASK`, `IRQ_ACK` | RO/RW | Completion- und Fehlerereignisse. |
| `CTX_ID` | RW | Aktueller Software-Kontext; später pro-Hart oder pro-Queue statt globalem Einzelwert. |
| `TIMEOUT` | RW | Obergrenze für CSB-/DMA-/Job-Wartezeiten; Timeout liefert Fehler statt endlosem Stall. |
| `SCHED_POLICY` | RW | `AUTO`, `PREFER_WEIGHT_REUSE`, `PREFER_INPUT_REUSE`, CBUF-Bank-/Release-Hinweise. Der Scheduler übersetzt dies nur, wo CDMA/CSC es unterstützen. |
| `DATAFLOW` | RW/RO | `NATIVE` ist für vorhandenes NVDLA gültig. `WS` und `OS` sind reserviert und liefern bis zu echter RTL-Unterstützung `UNSUPPORTED`. |
| `PERF_SELECT`, `PERF_VALUE` | RW/RO | NVDLA-Zähler und Controller-Zeiten wie Queue-, CSB- und DMA-Stalls. |

**OS/WS ist kein vorhandener globaler NVDLA-Schalter.** NVDLA besitzt
Gewichts- und Eingabewiederverwendung im CBUF und konfigurierbare
CDMA/CSC-Reuse-/Release-Felder. Die MAC-Stripes halten Gewichte zeitweise
konstant, während CACC Teilsummen akkumuliert. Das ist nicht dasselbe wie
ein zur Laufzeit umschaltbarer, allgemeiner Weight-Stationary-/Output-
Stationary-Datenpfad. `SCHED_POLICY` kann mit existierendem RTL Daten- und
Gewichts-Reuse beeinflussen. Für ein echtes `DATAFLOW=OS` oder `WS` müssten
CBUF/CSC/CMAC/CACC, Datenbewegung, Synchronisation und Verifikation
entsprechend geändert werden. Ein Register allein darf keinen solchen Modus
vortäuschen. Siehe [NVDLA Unit Description](https://nvdla.org/hw/v1/ias/unit_description.html)
und [Programming Guide](https://nvdla.org/hw/v1/ias/programming_guide.html).

## Deskriptor und unterstützte Operationen

Vorgeschlagener Deskriptor: 64-Byte-ausgerichteter, versionierter Header mit
`size`, `kind`, `flags`, 64-Bit-Adressen für Eingabe/Ausgabe/Gewichte/Aux,
Tensorformat und einem Zeiger auf einen typspezifischen Payload. Der Payload
enthält Dimensionen, Zeilen-/Surface-Strides, Kernel, Stride, Padding,
Dilation, Quantisierung sowie optionale Fusions- und Reuse-Angaben. Die
genaue C-Struktur wird zusammen mit dem ersten generischen `submit`
festgelegt; `size` erlaubt spätere Erweiterungen. Der Fetcher prüft Version,
Länge, Ausrichtung, Adressbereich, Überläufe, Tensorformat, benötigte
Capabilities und zulässige Abhängigkeiten **vor** dem ersten CSB-Write.

| Deskriptor-`kind` | NVDLA-Pfad | Für das aktuelle `nv_small` | Priorität |
| --- | --- | --- | --- |
| `SDP` | Offline SDP + SDP_RDMA: ReLU, Bias/Scale/BN, verfügbare Aktivierungen | BS und BN ja; EW und LUT hier deaktiviert | P0 |
| `CONV_DIRECT` | CDMA → CBUF → CSC → CMAC → CACC, optional SDP | INT8 Direct Convolution | P1 |
| `CONV_PIPE` | Zulässige Conv→SDP→PDP-Verkettung; sonst getrennte Jobs mit Abhängigkeit | Nur mit je Block/Verbindung geprüften Modi | P1 |
| `PDP` | PDP + optional PDP_RDMA: Max/Min/Mean-Pooling | Ja | P1 |
| `CDP` | CDP + CDP_RDMA: lokale Antwortnormalisierung | Ja | P1 |
| `RUBIK` | Layout-/Reshape-Operation | **Nein**, nur anderes NVDLA-Build | P2 |
| `BDMA` | Kopie zwischen Speicherinterfaces | **Nein**, BDMA und zweites Interface deaktiviert | P2 |
| `CONV_WINOGRAD`, `CONV_COMPRESSED`, `CONV_BATCH` | Optionale Convolution-Modi | **Nein** im aktuellen Build | P2 |

Diese Matrix folgt dem gepinnten [`nv_small.spec`](../../ext/nvdla/spec/defs/nv_small.spec)
und der [NVDLA-Blockarchitektur](https://nvdla.org/hw/v1/hwarch.html).
Auch andere NVDLA-Builds sind nicht automatisch „full feature“: ihre
Capabilities werden aus der jeweiligen Konfiguration erzeugt und von
`nd.cap` gemeldet. Die online dokumentierten CSB-Registeradressen können
von den für unser generiertes Profil erzeugten Headern abweichen; der
CSB-Sequencer verwendet deshalb ausschließlich die zum **selben Build**
gehörenden Registerdefinitionen.

## Scheduler, Speicher und Betriebssystem

1. Software legt Deskriptor und Tensoren in DMA-sichtbarem Speicher ab.
   `fence` ordnet Zugriffe, ersetzt aber **keine** Cache-Reinigung. Für den
   ersten Ausbau sind uncachebare oder explizit synchronisierte Buffer nötig.
   `nv_small` hat nur 32-Bit-NVDLA-Adressen; höhere Adressen werden abgelehnt
   oder erst nach einem separat entworfenen IOMMU/Bounce-Buffer-Konzept genutzt.
2. `submit` prüft Commit und holt den Deskriptor per eigenem AXI-Master über
   den bestehenden Crossbar. Der Controller validiert den gesamten Job und
   erzeugt erst dann einen Handle. Ein MMU/IOMMU-/Treiberkonzept muss
   verhindern, dass unprivilegierter Code beliebige DMA-Adressen einreicht.
3. Der Scheduler ordnet abhängige Jobs und setzt die NVDLA-Ping-Pong-
   Registergruppen korrekt. Er konfiguriert Pipeline-Stufen und setzt
   `D_OP_ENABLE` in der notwendigen Reihenfolge; für Convolution ist dies
   nach der [NVDLA Programming Guide](https://nvdla.org/hw/v1/ias/programming_guide.html)
   von nachgelagerten zu vorgelagerten Stufen. Zwei NVDLA-Registergruppen
   erlauben Vorbereitung, sind aber keine beliebig tiefe Hardware-Queue.
4. Abschluss wird über NVDLA-Interrupt/GLB und Blockstatus verfolgt;
   Polling bleibt ein Test-/Fallback-Pfad. Der Controller schreibt den
   Jobstatus, gibt den Handle frei und signalisiert bei Bedarf einen CPU-IRQ.
   Ein OS wartet auf IRQ oder nutzt `poll`, statt eine CV-X-IF-`wait`-
   Instruktion lange im CPU-Pipelinepfad zu halten. Vor CPU-Lesezugriffen
   auf DMA-Ausgaben ist gegebenenfalls Cache-Invalidierung nötig.
5. Ein fehlerhafter oder gekillter Job darf keinen Teil einer neuen
   Registergruppe aktivieren. Laufende Jobs sind nicht ohne Weiteres
   präemptierbar; `cancel` betrifft nur die Controller-Queue. Reset und
   Prozesswechsel brauchen definierte Drain-/Fehlerregeln.

## Umsetzung in Etappen und Abnahmekriterien

| Etappe | Umsetzung | Nachweis |
| --- | --- | --- |
| P0 | `cap`, `cfgwr/cfgrd`, Deskriptor-Fetch, `submit/poll/wait`, variable SDP-Größe/Strides; bestehendes `relu8` als Referenz | Cocotb: verschiedene Formen und Adressen, ungültige Deskriptoren, Commit-Kill, Timeout, Cache-/DMA-Reihenfolge. |
| P1 | Direct-INT8-Convolution mit Gewichten und CBUF, Conv→SDP, PDP-Pooling, CDP; Abhängigkeits-Handles | Referenzmodell-Vergleich für Conv/Pool/CDP, getrennte und verkettete Jobs, gleichzeitiger CPU-/NVDLA-AXI-Verkehr. |
| P2 | Ping-Pong-Auslastung, IRQ, mehrere Jobs/Kontexte, Perf-Zähler; optionale NVDLA-Builds mit EW/LUT, Winograd, Rubik oder BDMA | Capability-Matrix und Tests pro tatsächlich generiertem RTL-Profil; Job-Queue-/OS-Stresstests. |
| Forschung | Echte OS-/WS-Umschaltung nach RTL-Änderung und Flächen-/Bandbreitenanalyse | Numerische Korrektheit und Performance gegen `NATIVE`; erst dann `DATAFLOW`-Capability setzen. |

Der nächste konkrete Schritt ist **P0 mit einem versionierten SDP-Deskriptor**.
Damit werden Form, Adressen und Aktivierung erstmals zur Laufzeit frei
wählbar, ohne eine Instruktion pro NVDLA-Register oder pro Tensorparameter
einzuführen.
