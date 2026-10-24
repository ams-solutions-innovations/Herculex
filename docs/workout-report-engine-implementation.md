# Implementacija lokalnega poročila po treningu

Workout report engine je del aplikacije in ne uporablja AI ali omrežnega servisa. Osnovna različica vsebuje 29 identifikatorjev pravil za načrt in izvedbo, napredek, ponavljajoč padec, primerljivost, napor, spremembe volumna, supersete, različne merske enote ter neobvezen kontekst. Dolgoročni katalog iz analize ostaja okvir za širitev; trenutna pravila sklepajo samo iz podatkov, ki jih aplikacija dejansko ima.

## Uporabniška pot

Po zaključku treninga se na obstoječem zaključnem zaslonu pokaže kartica s številkami in največ tremi poudarki. Celotno poročilo, spremembe, razlika neposrednega/primarnega mišičnega dela in naslednji koraki se odprejo v podrobnostih. Ista kartica je v zgodovini končanega treninga.

Kontekst je neobvezen. Uporabnik lahko navede razlog sprememb, obrok pred treningom, nenavaden stres/utrujenost, bolečino in spremembo tehnike ali ROM. Neodgovorjeno ostane neznano. Ob zamenjavi vaje in odstranitvi delovne serije je na telefonu na voljo neobvezna izbira razloga. Report se po dopolnitvi konteksta ponovno izračuna.

Podprte primerjave uporabljajo isti exercise ID, fitnes, različico opreme, konfiguracijo naprave in dodatke ter primerljivo učinkovito obremenitev in zabeleženi RPE. Pri manjkajočem naporu, drugi postavitvi ali nerepetitivnem gibanju se ne ustvari običajna trditev o spremembi moči. Predlog dvojne progresije zahteva dve izpolnjeni predpisani izvedbi; uporabniku ostane pogoj, da sta bila tehnika in ROM primerljiva.

Spanec je časovno povezan z datumom treninga, osebni običajni vzorec pa zahteva vsaj sedem predhodnih vnosov v 28-dnevnem oknu. Vrednosti spanja ne določajo individualnega odstotka moči ali CNS. Obrok pred treningom se opira na uporabnikov odgovor; čas beleženja hrane se ne uporablja kot čas zaužitja.

## Podatki in življenjski cikel

Lokalna shema je v50. Dodane so tabele `workout_report_plans`, `workout_report_events` in `workout_reports`. Nobena nima sync stolpcev ali outbox triggerjev. Cloud migracija ni potrebna in reporti se ne sinhronizirajo.

Predpisan plan se zajame ob materializaciji. Za ročno sestavljen trening se shrani opazovani izhodiščni plan, vendar se ne razglasi za popoln predpis. Načrt se ohrani pred izbrisom serij ali vaj in pred čiščenjem nedokončanega dela ob zaključku. Sprejeta prilagoditev urnika ohrani tudi prvotno število serij in mišično razporeditev.

Menjava na telefonu po že opravljenih serijah ustvari novo vrstico za nadaljnjo izvedbo; dokončane serije ostanejo pri prvotni vaji. Polna popravljalna revizija z ure ohrani wire identitete, spremembo zabeleži in ne ustvarja primerjave stare in nove vaje kot iste naloge.

Zaključevanje shrani report tudi za pot z ure. Če poročilo ne uspe, trening ostane shranjen; odprtje zaključnega zaslona ali zgodovine ponovi izračun. Za popoln ogled uporabniške poti z uro ostaja potrebno preverjanje na fizičnih napravah.

SHA256 fingerprint vključuje uporabljene planirane in dejanske podatke, relevantno zgodovino, dogodke ter kontekst. Nespremenjeni podatki ne ustvarjajo nove revizije. Sprememba ustvari novo številko revizije in zamenja trenutno shranjeno poročilo; pregled vseh preteklih revizij ni del te različice. Verziji enginea, ruleseta in payload formata sta zapisani v rezultatu.

Report uporablja 84-dnevno okno zgodovine. Podatki iz prihodnjih treningov se izločijo. Običajni porabniki analitike še vedno lahko naložijo vso zgodovino. Vhodni zgodovinski podatki niso podvojeni v report tabeli: shranjen fingerprint je samo hash, rezultat pa vsebuje potrebna dejstva in razlage.

Izbris treninga odstrani njegove report tabele tudi pri izklopljenih foreign keys. Izbris računa jih vključuje v lokalni wipe. Izbris noči spanja odstrani tudi poročila iz obdobja, ki bi lahko uporabljalo to noč ali njen prispevek k osebnemu sleep baselineu.

## Predogled spremembe programa

Poročilo lahko ponudi pregled skromnega zmanjšanja dodatnega dela v prihodnji izvedbi, kadar pade več primerljivih benchmarkov in uporabnik prijavi nenavadno utrujenost. Pri nedokončanem treningu zaradi potrjene časovne omejitve lahko preveri obstoječi omejeni tedenski predlog prerazporeditve. Ni avtomatskega nadomeščanja namerno odstranjenega dela zaradi utrujenosti ali bolečine.

Predogled pokaže datum, ime treninga, število serij pred in po spremembi ter imena vaj. Dokler uporabnik ne potrdi, se ne zapiše adaptation override. Ob potrditvi se ponovno preverijo fingerprint poročila, stanje urnika in trenutni predpis. Zastarel predogled se zavrne. Sprememba velja za navedene pojavitve v urniku, ne prepisuje osnovnega programa.

## Prostor in meje

Devet novih produkcijskih Dart datotek je ob prvi meritvi zasedlo približno 73 KB izvorne kode. To ni meritev dodatka v APK/IPA; končna velikost je odvisna od prevajalnika in optimizacije. Obveznega prenosa enginea ni. Poročila so majhni JSON rezultati v lokalni bazi; ne vsebujejo PDF učbenika, videov ali slik uporabnika.

Osnovna različica ne diagnosticira vzrokov, pretreniranosti, dehidracije ali pomanjkanja glikogena. Ne meri dejanskega počitka, tehnike ali fiziološke regeneracije. Ne razglasi delnega prehranskega dnevnika za dokaz prenizkega vnosa in ne napoveduje odstotka prihodnje mišične rasti. Podrobnejši prehranski timing, opazovani ROM in obsežnejši športni kontekst potrebujejo dodatne zanesljive vhodne podatke.

## Preverjanje

Avtomatski primeri pokrivajo enkratni padec brez plateauja, ponavljajoče padce, manjkajoči RPE, spremenjeno opremo, napor, dvojno progresijo, neodgovorjen kontekst, nerepetitivne metrike, serijske spremembe, podvojeni zaključek, izbris zasebnih podatkov, zastarel predogled ter UI na ozkem telefonu. Migracijski testi preverjajo v49 v v50 in celotno podprto zgodovino shem. Vizualni pregled kartice je opravljen z dejanskimi pisavami na 390-pikslov širokem testnem telefonu.

Med širšim preverjanjem je bil posodobljen seznam pričakovanih foreign key povezav. Obstoječi test nastavitev je namesto čakanja na nov microtask stream znotraj fake clocka prebral že shranjeni profil; produkcijsko obnašanje profila je ostalo nespremenjeno.

Celotni testni paket je prestal s 3.134 uspešnimi in 9 preskočenimi testi. Po zadnjih dopolnitvah časovnih meja, fingerprinta in ponovnega odpiranja predogleda je prestalo še vseh 36 ciljnih testov reporta in prilagoditev; ločeno je prestal tudi nabor 65 testov s spanjem, regeneracijo in zaključnim zaslonom. Globalna statična analiza je brez napak, obstoječa opozorila drugod v projektu ostajajo. Fizično preverjanje telefona in ure še ni opravljeno.

Ponovljena ciljana analiza je pozneje naletela na napako zagona okolja `custom_lint`: klienta `.dart` je poskusil zagnati `dartaotruntime` kot AOT snapshot. To preverjanje vtičnika zato ni potrjeno, čeprav prejšnja globalna analiza ni našla Dart napak in so zaključni ciljni testi prestali.
