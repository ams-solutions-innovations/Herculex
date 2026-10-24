# Analiza determinističnega poročila po treningu

Datum: 14. oktober 2026. Status: predlog za pogovor pred implementacijo.

Herculex lahko po treningu pripravi kratko, uporabno poročilo brez AI. Izračun naj teče lokalno, razlage pa naj nastajajo iz verzioniranih pravil in pripravljenih besedil. Največji izziv ni velikost pravilnika, temveč zanesljivost vhodnih podatkov, primerljivost izvedb in ločevanje ugotovitev od hipotez o vzroku.

Pregled zajema zaključevanje treninga, načrtovane in opravljene serije, zamenjave vaj, analitiko, regeneracijo, spanec, prehrano, tedenska poročila, prilagajanje programa in meje lokalnih podatkov. Vir za programske odločitve je The Bodybuilding Programming Blueprint, različica 2.0 z dne 29. septembra 2026, PDF na uporabnikovem namizju s 71 stranmi in spremljajoča Wordova različica. Znanstvene ugotovitve o volumnu, prehrani in spanju so dodatno preverjene v spodaj povezanih raziskavah. To ni pregled vseh 272 izvornih videov niti preverjanje njihovih avtomatskih transkriptov proti zvoku.

Produkcijska koda, podatkovna shema in obstoječe nastavitve niso spremenjene. Ocene prostora so projektne ocene, ne meritve končnega paketa ali nameščene aplikacije.

## Kaj uporabnik dobi

Prvi prikaz po treningu naj odgovori na tri vprašanja: kaj je bilo opravljeno, kaj je pomembno odstopalo in kaj je smiseln naslednji korak. Na prvi ravni naj bodo največ tri poudarjene ugotovitve. Podrobnosti se odprejo po vaji, spremembi ali priporočilu.

Program lahko ugotovi, da je bilo pri isti obremenitvi opravljenih manj ponovitev. Iz tega samega ne more ugotoviti, da je razlog pomanjkanje glikogena, centralna utrujenost, bolezen ali slaba tehnika. Dober report pove, kateri podatki podpirajo razlago, kateri ji nasprotujejo in kaj ostaja neznano.

Predlagani tipi izhodov:

- **Ugotovitev:** neposredno iz dnevnika, na primer 21 opravljenih od 24 prvotno načrtovanih serij.
- **Sprememba:** uporabnik je odstranil tri dodatne serije ali zamenjal vajo.
- **Možen prispevek:** manj spanja od običajnega sovpada s padcem primerljive izvedbe.
- **Priporočilo:** pri naslednji izvedbi preveri eno spremenljivko in določi rok ponovne ocene.
- **Posledica načrta:** določena mišica ima ta teden dve neposredni seriji manj; naslednja obremenitev te mišice ostane v programu.
- **Omejitev podatkov:** nova naprava, drugačen ROM ali nepopolno beleženje onemogoča zanesljivo primerjavo.
- **Pozitiven rezultat:** napredovanje pri primerljivi izvedbi, uspešna prilagoditev ali dobro ohranjena prioriteta.

Oznake podpore naj bodo besedne: neposredno zabeleženo, podprto s ponavljajočim se vzorcem, možen prispevek, premalo podatkov. Brez odstotkov verjetnosti vzroka, dokler niso statistično kalibrirani.

## Kaj že obstaja v kodi

| Področje | Obstoječa osnova | Uporaba pri novem reportu |
|---|---|---|
| Arhitektura | Flutter, Riverpod, Drift SQLite, optional cloud sync | Lokalno ustvarjanje in ogled brez povezave |
| Zaključek | `lib/features/workouts/application/finish_workout_action.dart` | Shrani konec treninga; report je ločen, obnovljiv korak po uspešnem shranjevanju |
| Zaključni UI | `lib/features/workouts/presentation/views/workout_finish_view.dart` | Vstopna točka za kratek povzetek in podrobni report |
| Povzetek | `lib/features/workouts/domain/session_summary.dart` | Osnovne številke treninga |
| Načrt | `lib/features/workouts/data/planned_session_resolver.dart` in `planned_*` polja | Ciljne ponovitve, teža, napor, namen in vloga vaje ob začetku |
| Opravljene serije | `lib/data/local/tables.dart` | Teža, ponovitve, RPE, čas zaključka, vrsta serije, ogrevanje, opravljeno ali ne |
| Razrešena obremenitev | `lib/features/analytics/domain/training_snapshot.dart` | Telesna teža, pomoč, elastike, verige, dodatki in merski način |
| Volumen | `lib/features/analytics/domain/weekly_muscle_volume.dart` | Tedenske serije in ocenjen prispevek posameznim mišicam |
| Primerjave | `lib/features/analytics/domain/variant_performance.dart` | Različice opreme, dodatki in fitnes kot osnova za primerljivost |
| Regeneracija | `muscle_recovery_v3.dart`, `cns_trends.dart`, `cns_breakdown.dart` | Hevristična ocena obremenitve kot kontekst, ne dokazan fiziološki vzrok |
| Spanec | `lib/features/sleep/` | Ročni in zdravstveni vnosi, trajanje, zgodovina, možen kontekst |
| Prehrana | `FoodEntries`, prehranski snapshoti, nutrition repository | Zabeleženi dnevni makri in večdnevni trend |
| Prilagoditve | `weekly_adaptation_engine.dart`, `weekly_adaptation_repository.dart` | Predlogi in odločitve o zmanjšanju ali razporeditvi dela |
| Tedenski report | `lib/features/weekly_report/` | Vzorec shranjenega snapshot poročila in determinističnih kalkulatorjev |

Tedenski report vsebuje tudi ločeno pot za AI narrative. Nova funkcija je ne potrebuje. Smiselno je ponovno uporabiti matematične funkcije in način shranjevanja, ne klicati `WeeklyReportService.generateNarrative` ali generativnih servisov.

`TrainingSnapshot` je uporaben adapter, vendar sedaj naloži celotno zgodovino in izloči nedokončane ter ogrevalne serije. Sam ni dovolj za analizo načrt proti izvedbi. Novi input repository mora prebrati tudi izpuščene serije, začetni načrt in spremembe. Za dolge zgodovine naj uporabi omejena časovna okna in indeksirane poizvedbe.

## Vrzel pri podatkih in pomen za uporabnika

### Začetni načrt in spremembe

`planned_*` vrednosti ohranjajo več ciljnih podatkov. Ne ohranjajo pa samostojnega popolnega začetnega menija, če uporabnik odstrani vrstico ali zamenja ID vaje.

`WorkoutsRepository.deleteSet` trenutno izbriše serijo in njene povezane dodatke. Brez ločenega načrta ali dogodka ni mogoče vedeti, ali je bila serija namenoma odstranjena, izpuščena zaradi časa ali sploh prvotno načrtovana.

`substituteExercise` zamenja `exerciseId` na obstoječi vrstici vaje, ponastavi različico opreme in očisti obremenitve nedokončanih serij. Če vrstica že vsebuje opravljene serije, te ostanejo povezane z isto vrstico vaje. Razreševanje skozi trenutni `exerciseId` zato lahko pretekle opravljene serije pripiše zamenjavi. Pred uporabo teh podatkov za report je treba zamenjavo po opravljeni seriji razdeliti na ločeni izvedbi ali ohraniti identiteto vaje ob izvedbi serije.

Predlagana minimalna dopolnitev je neodvisen začetni snapshot in strukturiran dnevnik sprememb: dodana/odstranjena serija, zamenjana vaja, sprememba vrstnega reda, cilja ali tehnike ter izvor spremembe. Pri zamenjavi je pomembno tudi, ali velja za to izvedbo ali prihodnji program.

### Prehrana in čas obroka

`FoodEntries.loggedAt` označuje čas beleženja. Ni nujno čas zaužitja. Uporabnik lahko večerjo vnese naslednji dan ali vse obroke zvečer. Engine iz tega polja ne sme izračunati, da je uporabnik jedel določeno količino ogljikovih hidratov dve uri pred treningom.

Za časovne razlage potrebujemo ločen `consumedAt` ali preprost podatek, ali je uporabnik jedel pred treningom in približno kdaj. Dnevnik mora razlikovati tudi popoln dan beleženja od delnega. Manjkajoči obroki niso dokaz nizkega vnosa.

### Počitek in tehnika

`targetRestSeconds` je cilj. Razlika med dvema `completedAt` ni čist čas počitka: vsebuje trajanje naslednje serije, zamik vnosa, prehod na napravo in morebitne prekinitve. Za zanesljivo trditev o kratkem počitku potrebujemo dogodek začetka serije ali potrjeno dejansko trajanje počitka.

Načrtovani RIR obstaja, opaženi napor pa je večinoma RPE. Pretvorba RPE v RIR je približek. Tehnike in ROM aplikacija iz navadnih številk ne vidi. Zadostuje kratka uporabnikova oznaka spremembe; samodejno sklepanje o tehnični odpovedi ali krajšem ROM ni upravičeno.

### Zdravstveni kontekst in zgodovina

Zdravstveni podatki so lokalni. Report mora shraniti izvor, relevantni čas in svežino vsakega uporabljenega signala. Pri poznem urejanju starega treninga ne sme uporabiti današnjega spanja ali današnjih prehranskih ciljev kot takratnih podatkov.

Izračun predtrening obremenitve mora biti narejen s časom začetka treninga in brez njegovega opravljenega dela. Sicer današnja serija poveča današnji fatigue score, engine pa to napačno uporabi kot razlog, da ta ista serija ni uspela.

## Kaj iz učbenika sodi v engine

| Del učbenika | Prevod v obnašanje reporta |
|---|---|
| I, poglavja 1–3 | Loči moč, hipertrofijo, vzorce in meritve; označi evidence in coaching heuristike |
| II, 4–7 | Zamenjave po vlogi in mišici, stabilnost postavitve, omejitev prijema ali ravnotežja, drugačna cena utrujenosti |
| III, 8–12 | Vrstni red, overlap, volumen, napor, počitek, ROM, dvojna progresija in trajen plateau |
| IV, 13–17 | Različne potrebe novinca, povratnika, intermediate in advanced; nivo je lahko specifičen za vajo |
| V, 18–21 | Pojasni distribucijo, planirano menjavo območja ponovitev, concurrent trening in fazo energijskega vnosa |
| VI, 22–26 | Primerjaj dejansko delo in napor, ne ideologije; napredne metode niso avtomatsko boljši stimulus |
| VII, 27–29 | Več zaporednih signalov pred večjo spremembo, spanec in stres kot kontekst, brez odplačevanja vseh zamujenih serij |
| VIII, 30–32 | Energija, telesna masa, prehranska zadostnost in zahtevnost treninga; dodatki niso osnovna rešitev |
| IX, 33–35 | Osebne omejitve, oprema, čas in preference; uporabniško prijavljeni simptomi imajo prednost |
| X, 36–44 | Razlage za kratke treninge, specializacijo, endurance, nižji/višji volumen in povratek |
| XI, 45–50 | Loči plan in izvedbo; pravilo ima ID, pogoje, izjeme in razlog; sprememba ohrani predhodno in naslednje stanje |
| XII, 51–58 | Izvedljivi logi, cadence pregledov, decision tables, substitutions, coverage in korekcije mitov |

Osrednja pravila za poročanje:

- `PROGRESSION-DOUBLE-01`: povečanje obremenitve predlagaj po dveh primerljivih izvedbah, kjer vse načrtovane serije dosežejo zgornjo mejo pri ciljnem naporu in stabilni tehniki.
- `PROGRESSION-PLATEAU-02`: vsaj tri primerljive izpostavitve brez izboljšanja so razlog za pregled konteksta, ne dokaz premalo volumna.
- `REST-PERFORMANCE-01`: če podatki podpirajo prekratek počitek, preveri počitek ali konkurenco superseta pred dodajanjem serij.
- `VOLUME-OVERLAP-02`: neposredne serije in ocenjen indirect contribution prikaži ločeno.
- `VOLUME-GUARD-03`: približno 18 tedenskih serij ali dvig za več kot dve seriji je produktni review trigger, ne univerzalni maksimum.
- `SPECIALIZE-PRIORITY-01`: pri stagnaciji prioritete in dobri regeneraciji najprej lokalna sprememba, po potrebi prerazporeditev nižje prioritete.
- `RECOVERY-ADJUST-01`: ponavljajoč padec več benchmarkov in vztrajna utrujenost podpirata ponudbo lažjega obdobja.
- `RECOVERY-MISSED-02`: izpuščena izvedba ne ustvarja obveznega dolga vseh serij.
- `CONCURRENT-SPORT-01`: upoštevaj zahtevne zunanje aktivnosti; lahek sprehod ni enakovreden intervalnemu teku.
- `VALIDATE-PLAN-01`: po predlagani spremembi preveri izvedljivost, overlap, prioritete in omejitve.

Učbenik vsebuje 34 osnovnih rule IDs, kar je izhodišče za programe, ne že pripravljen katalog vseh reportov. Reporting potrebuje dodatna pravila za kakovost podatkov, primerljivost, dogodke, rangiranje, konflikt in pozitivne rezultate.

## Neskladja za razrešitev pred implementacijo

**Deload v učbeniku.** Poglavje 28 in `RECOVERY-ADJUST-01` predlagata približno 20–30 % manj serij, poglavje 53 pa približno tretjino do polovico. Oboje je heuristika. Predlog je ena politika z različnimi konteksti: manjša prilagoditev posamezne izvedbe in ločeno večdnevno razbremenjevanje. Obseg mora izhajati iz opaženega vzorca in prioritete, brez trditve o znanstveno določenem idealnem odstotku.

**Volumenski pragovi v kodi.** `VolumeBands.priors` in `MuscleRecoveryV3.defaultWeeklyMrv` uporabljata različne številke. Na primer chest maximum je v obeh 22, hamstrings pa 20 v builderju in 16 v recovery; side delts 26 proti 25. Pomeni so deloma različni, zato jih ni pravilno slepo združiti. Skupni pravilnik mora povedati, katera je smernica načrtovanja, katera warning threshold in koliko podpore ima personalizacija.

**CNS prikaz.** `CnsTrends` in `CnsBreakdownEngine` iz seštevka serij, napora, exercise cnsScore in časovnega razpada izpeljeta obremenitev. To je model, ne meritev centralne utrujenosti. Besedilo, kot je »CNS fully primed«, ne sme postati dokaz vzroka ali zagotovilo za PR. ACWR trigger sam po sebi ne dokazuje, da je uporabnik presegel svojo resnično regeneracijsko sposobnost.

**Spanec in točni odstotki.** `SleepWeightliftingEngine` uporablja fiksne CNS in strength odstotke ter kategorične fiziološke razlage, na primer da je repair zaključen ali da je hitrost palice zmanjšana za določen odstotek. Ti individualni izidi niso izmerjeni z urami spanja. Novi report naj uporablja zabeleženo trajanje in osebni običajni vzorec kot kontekst, ne teh številk kot dejstva.

**Korelacije.** `SleepLiftingCorrelation` omogoča interpretacije že po treh treningih in primerja tudi skupno tonažo. Menjava programa ali števila serij lahko sama spremeni tonažo. Za osebne razlage potrebujemo primerljive izvedbe, dovolj opazovanj in besedilo o povezanosti; šibka korelacija ne dokazuje, da je izvedbo povzročilo programiranje.

## Katalog možnih scenarijev

Spodnji katalog je obseg analize, ne že implementiran ali validiran ruleset. Posamezna situacija se lahko združi z drugimi. Za vsak rule je treba zapisati minimalne podatke in izključitvene pogoje.

| Skupina | Situacije, ki jih mora engine razlikovati | Pogoj za uporabno razlago |
|---|---|---|
| Pozitiven napredek | Več ponovitev pri isti teži; več teže pri podobnih ponovitvah; nižji opaženi napor; uspešna nova vaja; ohranjena moč ob manj dela; večina ciljev dosežena | Enaka ali jasno opredeljena primerljiva izvedba |
| Enkraten slabši rezultat | Slab prvi set; padec šele pozno; ena slabša vaja; vsi benchmarki slabši; en izpuščen set; brez težave v naslednji izvedbi | Brez avtomatske oznake plateau |
| Trajen vzorec | Tri primerljive izvedbe brez progresije; padajoča serija benchmarkov; ponavljajoč padec ene mišične skupine; napredek drugje; nestabilen rezultat zaradi menjav | Stabilni pogoji in dejansko opravljeni treningi |
| Napor in obremenitev | Prevelik korak teže; prvi set do odpovedi; prelahki seti po uporabnikovem RPE; previsok načrt za novo vajo; namenoma lažji teden; manj ponovitev po načrtovanem povečanju teže | Loči načrtovano spremembo od nepričakovanega poslabšanja |
| Počitek in vrstni red | Potrjeno krajši počitek; competing superset; pre-exhaustion; prioriteta prestavljena pozno; daljši počitek izboljša naslednjo izvedbo; časovni pritisk | Dejanski rest ali uporabniška potrditev, ne samo timer target |
| Menjave vaj | Oprema zasedena; bolečina; preference; načrtovana rotacija; nova varianta; menjava naprave; več stabilnosti; manj aksialne obremenitve; slabše pokrita ciljna mišica; ohranjen movement role | Začetna vaja in razlog morata ostati v dogodku |
| Zmanjšanje volumna | Namenska autoregulacija; premalo časa; izpuščena prioriteta; odstranjena redundanca; manj neposrednega dela ob ohranjenem overlapu; deload; začasna ali trajna sprememba | Začetni načrt, odločitev in prihodnji razpored |
| Povečanje volumna | Dodatna prioritetna serija; dodatni redundantni koti; dvig več mišicam hkrati; velik skok proti osebni zgodovini; več serij ob slabšem naporu; izvedljiva prerazporeditev | Ne razglasi vsake dodatne serije za dodatno rast |
| Lokalna utrujenost | Kratka razdalja med izpostavitvama; nov ekscentričen stimulus; uporabniško prijavljena bolečina/soreness; velika press-arm ali pull-arm prekrivanja; omejitev grip; omejitev ravnotežja | Model obremenitve in uporabniški signal naj se ne pretvarjata v diagnozo |
| Sistemski kontekst | Več slabših benchmarkov; slabša motivacija; visok zabeležen stres; potovanje; illness report; delovne obremenitve; demanding sport; dolga pavza | Potrditev ali zanesljiv podatek; unknown ne pomeni absent |
| Spanec | Ena kratka noč; več krajših noči; manj kot osebni običajni vzorec; shift schedule; ročni vnos; stara meritev; manjkajoči podatki | Relevantna noč pred treningom in izvor podatka |
| Prehrana | Potrjen trening na tešče; dolg presledek od obroka; manj ogljikovih hidratov ob dolgem/obsežnem treningu; večdnevni energijski primanjkljaj; ustrezen zabeležen vnos; delni dnevnik; nizek trend proteinov | Timing in completeness morata biti eksplicitna |
| Hidratacija | Potrjeno malo pitja; uporabniško prijavljena vročina ali veliko znojenja; običajen dnevni vnos; dnevna voda brez časovne povezave | Dnevni water log sam ne dokazuje dehidracije med treningom |
| Bodyweight kontekst | Težji pull-up ob višji telesni masi; manj pomoči; več dodane teže; drugačna elastika; padanje mase med cut; izboljšanje relativne izvedbe | Primerjaj učinkovito obremenitev in enak način izvedbe |
| Napredne metode | Drop set; rest-pause; myo-reps; partials; pause reps; clusters; supersets; povratek na straight sets | Ne enači metod s točnim številom ekvivalentnih hard sets |
| Druge merske enote | Plank čas; carry razdalja; sled push; erg calories; circuit pacing; calisthenics level change | Ločeni kalkulatorji, brez prisilne e1RM ali tonaže |
| Kakovost podatkov | Brez zgodovine; manjkajoč RPE; nerealistična teža; pozni vnosi; duplikati watch/phone; urejen star trening; sprememba enot; zastarel kontekst | Podatkovna napaka ima prednost pred fiziološko razlago |
| Prihodnji program | Naslednja izpostavitev prioritete; premajhen razmik; delno nadomeščanje izpuščenega dela; opustitev volume debt; predlog za eno lokalno spremembo; sprejet/odklonjen predlog | Vedno preveri trenutni razpored pred potrditvijo |

Obsežen katalog ne pomeni, da bo uporabnik videl vse možne razloge. Engine izbere relevantne, združi sorodne in zavrne tiste, ki jih podatki ne podpirajo. »Premalo karbov« se ne sme avtomatsko pojaviti pri vsakem slabem treningu.

## Prehrana in fiziološke razlage

Pregled 49 raziskav o ogljikovih hidratih je našel veliko kontekstov brez izboljšanja izvedbe ob višjem vnosu; koristi so bile bolj vidne pri postu in zelo obsežnem delu. Druga meta-analiza prav tako obravnava akutno hranjenje glede na kontekst treninga. Za engine to pomeni kombinacijo pogojev: potrjena prehranska situacija, zahtevnost treninga in vzorec izvedbe. Število deset serij na mišico iz pregleda ni osebni diagnostični prag. [Henselmans 2022](https://pubmed.ncbi.nlm.nih.gov/35215506/), [King 2022](https://pubmed.ncbi.nlm.nih.gov/35809162/).

Izguba spanja je na ravni skupin povezana s slabšo telesno izvedbo, odziv pa se razlikuje med nalogami in protokoli. To podpira razlago možnega prispevka spanja, ne natančnega odstotka današnje moči posameznika. [Craven 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9584849/).

Meta-regresija volumna podpira pozitivno povezavo z napredkom in padajoče dodatne donose. Ločevanje neposrednih in posrednih serij pomaga modeliranju. Iz tega ne sledi individualna napoved izgubljene rasti po odstranitvi dveh serij. [Pelland 2026](https://pubmed.ncbi.nlm.nih.gov/41343037/). Aktualna ACSM sinteza prav tako obravnava rezultate za zdrave odrasle in več različnih ciljev. [Currier 2026](https://pubmed.ncbi.nlm.nih.gov/41843416/).

Pri prehrani in regeneraciji je treba ločiti akutno izvedbo od dolgoročne prilagoditve. Nizek večdnevni vnos proteinov je razlog za pregled prehrane; sam po sebi ni dokaz, zakaj je danes odpovedala zadnja serija.

## Predlog arhitekture

Nova funkcija naj sledi obstoječi feature-first organizaciji, na primer `lib/features/workout_report/`, s plain-Dart domainom, input repositoryjem, application controllerjem in UI.

Pot izračuna:

1. Trening se uspešno shrani. Report failure ne sme preprečiti shranjevanja.
2. Repository sestavi časovno omejen input snapshot: začetni načrt, dejanska izvedba, dogodki, ustrezne primerjave in takratni kontekst.
3. Validator označi completeness, napačne podatke, svežino in primerljivost.
4. Kalkulatorji izračunajo dejstva, trende in neposredne posledice sprememb.
5. Pravila ustvarijo kandidate z dokaznimi referencami, izjemami in uporabniško razumljivo podporo.
6. Resolver združi podvojene razloge, razreši konflikte in izbere najpomembnejše ugotovitve.
7. Renderer vstavi podatke v lektorirane predloge besedil.
8. Persistira se verzioniran rezultat. UI ga prikaže; podrobnosti so dosegljive tudi pozneje.

Pravilo potrebuje ID, verzijo, tip, obvezne inpute, preverjanje pogojev, izključitvene pogoje, prednost, skupino konflikta, razred dokazov, chapter/source reference, besedilno predlogo in rok ponovne ocene. Ocena podpore kandidata ni verjetnost fiziološkega vzroka.

Prednost odločanja: eksplicitni pomembni simptomi in osebne omejitve, kakovost podatkov, primerljivost, neposredna dejstva, ponavljajoči vzorec, nato kontekstualne hipoteze. Več razlogov je lahko hkrati smiselnih, priporočila pa morajo tvoriti skladen naslednji korak.

Zgodovina mora imeti stabilno identiteto session UUID, revision/fingerprint vhodnih podatkov, engine version, rules version in content/locale version. Podvojena phone/watch zaključka ustvarita isti rezultat, ne dveh reportov. Report nastane tudi po zaključku na uri ali ob naslednjem odprtju aplikacije. Deluje lahko kot obnovljivo opravilo; napaka prikaže shranjeni trening in možnost ponovitve reporta.

Pri urejanju je treba stare razloge označiti kot temelječe na prejšnji reviziji in ustvariti novo revizijo. Novi ruleset ne sme tiho prepisati zgodovine. Izbris treninga odstrani vezani report. Izbris zdravstvenih podatkov mora zajeti tudi občutljive izpeljanke v reportih in input snapshotih.

### Posledice sprememb

Engine naj primerja tri stanja: prvotni načrt, uporabljeni prilagojeni načrt in dejansko opravljeno delo. Tako razlikuje »opravil si celoten lažji načrt« od »nisi dokončal treninga«.

Za prihodnost sta smiselna dva izhoda. Prvi je natančen izračun načrta: koliko neposrednih serij manj/več, kateri movement role manjka, koliko okvirnega časa se spremeni in kateri prihodnji trening je relevanten. Drugi je pogojna smerna razlaga: manj dodatnega dela lahko zmanjša utrujenost, trajno zmanjšanje prioritete pa lahko zmanjša njeno priložnost za napredek. Rast, injury risk in čas regeneracije niso natančno napovedljivi iz števila serij.

Predlog nikoli tiho ne spremeni programa. Pred potrditvijo ponovno preveri aktualno stanje, saj se je urnik lahko medtem spremenil. Obstoječi weekly adaptation flow je možen izvajalec potrjene spremembe, vendar potrebuje usklajeno politiko za catch-up in namensko zmanjšanje.

## UI in potrebni vnosi

Na zaključnem zaslonu naj ostane občutek uspešno shranjenega treninga. Dodaj kratek report:

- opravljeno delo, trajanje in en jasen dosežek ali odstopanje;
- »Kaj se je spremenilo« za odstranjene serije in zamenjave;
- največ dva najbolj podprta možna prispevka;
- en izvedljiv naslednji korak;
- gumb za analizo posameznih vaj in pojasnilo podatkov.

Primer fiktivnega reporta: »Opravil si vseh 21 serij prilagojenega načrta. Iz prvotnega načrta si odstranil tri dodatne serije. Glavne vaje so ostale. Pri benchu si pri isti teži opravil dve ponovitvi manj; ena izvedba še ne pomeni plateauja. Pred treningom si zabeležil manj spanja kot običajno. Pri naslednji izvedbi ohrani postavitev in preveri rezultat pred nadaljnjo spremembo volumna.«

Če uporabnik ni potrdil časa obroka, report pove, da prehranskega timinga ni mogoče oceniti. Zamenjave naprave ne prikazuje kot izgubo moči. Poročilo naj bo pozitivno tudi ob smiselni autoregulaciji.

Za bogate razloge je potreben minimalen check-in, ki ga je treba produktno uskladiti. Predlog: sprememba zaradi časa, utrujenosti, bolečine, opreme ali preference; pri kontekstu možnost »jedel pred treningom«, »nenavaden stres/utrujenost« in »bolečina«. Vnos je neobvezen, vprašanje naj se pojavi le tam, kjer izboljša razlago. Izpustitev pomeni unknown. Brez teh podatkov engine ponudi bolj omejeno, vendar pošteno analizo.

Report se odpre tudi iz zgodovine treningov. Osnovni prikaz ne potrebuje wall-of-text ali PDF. Share card naj ima ločeno vsebino od zasebnih zdravstvenih razlag.

## Shranjevanje in velikost

| Sestavina | Predlagano mesto | Razlog |
|---|---|---|
| Programska logika | Dart v aplikaciji | Hiter determinističen izračun brez omrežja |
| Osnovni rule/content paket | Bundled asset | Deluje takoj in offline |
| Posodobitve podatkov pravil | Po potrebi strežnik, lokalno verificiran paket | Različice, rollback in manjša potreba po app release za besedila |
| Uporabniški inputi | Lokalni Drift | Prehrana, spanec in trening že imajo lokalno osnovo |
| Reporti in spremembe | Lokalni Drift | Ogled zgodovine, revizije in reprodukcija |
| Sinhronizacija reportov | Opcijsko, po izrecni odločitvi o obsegu | Report lahko razkrije izpeljane zdravstvene informacije |
| Celoten PDF in video arhiv | Razvojna/referenčna dokumentacija | Za runtime ni potreben; ne vključuj ga zgolj za izračun |

Pomembna meja: če report vsebuje rezultat iz lokalnega spanja ali drugih zdravstvenih signalov, njegov cloud sync vseeno prenese izpeljane zdravstvene podatke. Odsotnost raw samples ne pomeni, da je ohranjena današnja local-only meja. Priporočena začetna odločitev je local-only report, cloud sync pa ločena produktna odločitev z jasno vsebino, izbrisom in dostopom.

Pravila je mogoče deliti na prenosljive podatke in implementacijo algoritmov. Podatkovni paket ne sme biti poljubna prenesena izvedljiva koda. Potrebuje shemo, seznam dovoljenih operatorjev, omejitev velikosti, preverjeno integriteto/izvor, združljiv engine version in atomarno aktivacijo. Stari delujoči paket ostane fallback.

Ocena velikosti strukturiranih pravil z razlagami v enem ali dveh jezikih:

| Obseg | Okvirna nekompresirana vsebina |
|---|---|
| 200 bogatejših pravil | Približno 0,3–1 MB |
| 1.000 pravil | Približno 1–5 MB |
| 5.000 pravil | Približno 5–25 MB |
| Shranjen rezultat ene izvedbe | Projektna ocena 5–30 KB brez slike in podrobnega raw trace |
| 1.000 takih rezultatov | Približno 5–30 MB payloadov; dodatno indeksi, SQLite strani, snapshoti in revizije |

Za merilo je bil serializiran sintetični primer pravila s pogoji, izjemami, referencami in štirimi besedili v dveh jezikih. 200 zapisov je zasedlo 274.401 B, 1.000 zapisov 1.372.001 B in 5.000 zapisov 6.860.001 B. Sintetični report z 12 ugotovitvami je imel 3.476 B. To potrjuje red velikosti, ne realne vsebine. Sintetične ponovitve se zelo dobro komprimirajo, zato njihove gzip velikosti niso uporabna ocena produkcijskega prenosa. Končni paket je treba izmeriti po pripravi raznolikih pravil in prevodov.

Uporabnikov referenčni PDF ima 1.145.221 B, približno 1,09 MiB; Wordova kopija ima 185.326 B. To sta velikosti konkretnih referenc, ne enginea.

Ni potrebe po predizračunu vsake kombinacije vseh razlogov. Deljena pravila in parametrizirane predloge se sestavijo ob izračunu. Veliko možnih reportov zato ne pomeni sorazmerno velike datoteke vseh reportov.

Osnovni engine priporočam vključiti v aplikacijo. Opcijski prenos je smiseln za dodatne jezike, obsežne razlage, referenčne ilustracije ali specializirane module, če realne meritve pokažejo potrebo. Uporabnik naj tedaj vidi ločeno velikost prenosa, zasedenega prostora in potreben začasni prostor za posodobitev. Število pravil samo ni dober razlog, da osnovna funkcija zahteva download.

## Predlagane faze

1. **Pogodba podatkov in odločitev.** Uskladi načrt/izvedbo, dogodke sprememb, prehranski timing, check-in, zasebnost in besedilo negotovosti.
2. **Sledljivost.** Ohranjen začetni načrt; zamenjava po opravljenih serijah; razlogi za odstranitev; povezava na sprejete prilagoditve.
3. **Deterministične ugotovitve.** Plan proti izvedbi, primerljiva zgodovina, napredek, zamenjave in neposredne posledice za mišice ter urnik.
4. **Kontekst in priporočila.** Evidence register, spanje/prehrana/stres, konflikti, testni primeri in znanstveno primerna besedila.
5. **UI in življenjski cikel.** Kratek zaključni report, podrobnosti, history, watch finish, resume, revizije in izbris.
6. **Širitev pravilnika.** Dodatne metode, populacije in moduli šele s podatki in validacijo; meritve časa, prostora in koristnosti.

Prvi uporabni del naj ima manj pravil z dobro sledljivostjo. Dolgoročni katalog lahko vsebuje stotine pravil in veliko kombinacij, vendar mora vsaka dodatna razlaga izboljšati relevantnost, ne samo dolžine.

### Preverjanje pri implementaciji

Potrebni primeri vključujejo: ena slabša izvedba brez plateauja; nova naprava brez false regression; namenoma odstranjen accessory brez failure ocene; opravljene serije pred zamenjavo z ohranjeno identiteto; delni prehranski log brez underfueling trditve; pozni food log brez timing trditve; utrujenost pred treningom brez vključitve njegovega dela; watch/phone dvojni zaključek; offline nastanek; sprememba starega treninga z novo revizijo; unknown RPE; non-rep workout; konflikt med priporočilom počitka in dodajanja volumna; izbris občutljivih izpeljank.

Poleg avtomatskih primerov je potreben pregled besedil: vsaka personalizirana trditev mora imeti input in rule reference. Primerljivo opažanje, smerna posledica načrta in fiziološka hipoteza morajo ostati jasno ločeni.

## Potrjene produktne odločitve

Potrjeno 14. oktobra 2026: uporabnik se strinja s kratkim, neobveznim vnosom razloga ob spremembi treninga (čas, utrujenost, bolečina, oprema ali preferenca) in osnovnega konteksta pred treningom. Preskočen vnos pomeni neznan podatek in ne sme sprožiti domnevnega razloga. Potrditev velja za to produktno odločitev; implementacija še ni naročena.

Potrjeno 14. oktobra 2026 tudi: kratek povzetek se pokaže samodejno po treningu; report se sprva hrani lokalno; priporočena sprememba prihodnjega programa ima predogled in se izvede šele po uporabnikovi potrditvi. Potrditev določa osnovno obnašanje funkcije in ne pomeni začetka implementacije.

Priporočen začetni odgovor je: samodejen kratek povzetek, neobvezen kontekst, lokalno shranjevanje in priporočila s potrditvijo vsake spremembe programa. Engine in osnovna pravila so vključeni v aplikacijo. Brez AI in brez obveznega dodatnega prenosa.
