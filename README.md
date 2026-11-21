# Orbit IPTV för Android TV

Flutter-app med mpv som videomotor (via media_kit). Styrs helt med fjärrkontrollen.
Version 1: inloggning (Xtream), Filmer, Serier, Live, spola och **fortsätt titta**.

## Så får du appen på din TV (utan att installera något på datorn)

1. Skapa ett gratis konto på <https://github.com>.
2. Klicka **New repository**. Namn: `orbit-tv`. Välj **Public** (appen innehåller inga lösenord eller konton – de skrivs in på TV:n).
3. På den nya sidan: klicka **uploading an existing file**. Öppna mappen *Orbit Android App* på din dator, markera **allt som ligger i den** (inklusive mappen `.github`, `lib`, `tool` och filerna) och dra in det i webbläsaren. Klicka **Commit changes**.
4. Gå till fliken **Actions**. Bygget "Bygg APK" startar av sig självt (ca 10 minuter). Blir det ett rött kryss: öppna körningen, kopiera felet och skicka det till Claude.
5. När det blir grönt finns APK-filen under **Releases → Orbit TV (senaste bygget)**.
   Direktlänk (byt ANVÄNDARNAMN): `https://github.com/ANVÄNDARNAMN/orbit-tv/releases/download/senaste/orbit-tv.apk`
6. På TV:n: öppna **Downloader**, skriv in länken, ladda ner och välj **Installera**. Tillåt "okända källor" om TV:n frågar.

## Styrning
- Piltangenter flyttar markeringen, **OK** väljer.
- I spelaren: vänster/höger = spola (håll in = större hopp), OK = paus/spela, upp/ner = visa tid, Tillbaka = stäng.

## Viktigt
Använd bara tjänster du har laglig rätt att använda. Appen levererar inget innehåll.
