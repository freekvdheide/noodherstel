#!/bin/bash
# herstel.sh - bootstrap voor een LEGE Mac. Zet gereedschap klaar, maakt een ALLEEN-LEZEN koppeling met de backup,
# haalt het herstelpakket op en zet de rem. Kopieert verder NIETS terug. Het echte herstel doet Claude Code met
# ~/NOODHERSTEL/HERSTEL-PLAN.md. Geen sudo in dit script (alleen de Homebrew-installer vraagt zelf om je wachtwoord).
# Draaien: eerst downloaden, sha256 vergelijken met het papier, dan:  bash herstel.sh
set -u
say(){ printf '\n== %s\n' "$1"; }
die(){ printf '\nSTOP: %s\n' "$1"; exit 1; }

[ "$HOME" = /Users/freek ] || die "Gebruikersnaam is niet freek (HOME=$HOME). Maak eerst de gebruiker freek aan; alles in de backup verwijst naar /Users/freek."

say "1/7 Xcode Command Line Tools (git). Verschijnt er een venster: klik Installeer en wacht."
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  W=0; until xcode-select -p >/dev/null 2>&1; do sleep 15; W=$((W+15)); [ $((W % 300)) -eq 0 ] && echo "  ... nog aan het wachten op de Xcode-installatie ($((W/60)) min)"; [ $W -ge 1800 ] && die "Command Line Tools na 30 min nog niet aanwezig. Installeer via: xcode-select --install, en draai dit script opnieuw."; done
fi

if [ "$(uname -m)" = arm64 ]; then
  say "2/7 Rosetta (voor de FDA-launcher van de backup)"
  /usr/bin/pgrep -q oahd || softwareupdate --install-rosetta --agree-to-license || true
fi

say "3/7 Homebrew (vraagt één keer om je Mac-wachtwoord)"
if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
B=/opt/homebrew/bin/brew; [ -x "$B" ] || B=/usr/local/bin/brew; [ -x "$B" ] || die "Homebrew niet gevonden na installatie."
eval "$("$B" shellenv)"
grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null || printf '\neval "$(%s shellenv)"\nexport PATH="$HOME/.local/bin:$PATH"\n' "$B" >> "$HOME/.zprofile"
brew install rclone gh age >/dev/null || die "brew install rclone gh age mislukte."
command -v rclone >/dev/null || die "rclone niet op PATH na installatie."

say "4/7 Claude Code (native installer)"
export PATH="$HOME/.local/bin:$PATH"
command -v claude >/dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash
command -v claude >/dev/null 2>&1 || die "claude niet gevonden na installatie."

say "5/7 ALLEEN-LEZEN toegang tot de backup. Er opent een Google-inlogscherm: kies freek@wearefireworx.com."
echo "     (Op de vraag 'Configure this as a Shared Drive' is het antwoord n.)"
if ! rclone listremotes 2>/dev/null | grep -q '^gdrive-restore:$'; then
  printf 'n\n' | rclone config create gdrive-restore drive scope drive.readonly
fi
if ! rclone lsd gdrive-restore:BACKUP-FREEK-MAC/current >/dev/null 2>&1; then
  rclone config delete gdrive-restore 2>/dev/null
  die "Kan BACKUP-FREEK-MAC niet lezen. Verkeerd Google-account gekozen? Draai dit script opnieuw."
fi
# bewijs dat deze koppeling niets KAN schrijven; anders is de hele bescherming van het herstel weg
if rclone touch gdrive-restore:BACKUP-FREEK-MAC/.ro-test >/dev/null 2>&1; then
  rclone config delete gdrive-restore 2>/dev/null
  die "De koppeling kon schrijven naar de backup; dat mag niet. Verwijderd. Draai opnieuw en meld dit."
fi

say "6/7 Herstelpakket ophalen naar ~/NOODHERSTEL"
mkdir -p "$HOME/NOODHERSTEL"
P="gdrive-restore:BACKUP-FREEK-MAC/current/home/PROJECTS/DRIVE-BACKUP/noodherstel"
rclone copy "$P" "$HOME/NOODHERSTEL" --exclude 'launchagents/**' --exclude 'pakket/**' -q
rclone copy "$P/pakket" "$HOME/NOODHERSTEL" -q
for f in HERSTEL-PLAN.md fase2.sh fase3.sh Brewfile exec-bits.txt symlinks.txt tellingen.txt ARCHITECTUUR.md; do
  [ -f "$HOME/NOODHERSTEL/$f" ] || die "$f ontbreekt in het pakket. Haal de map 00-NOODHERSTEL uit Google Drive en meld dit."
done

say "7/7 De rem zetten: de backup-jobs doen niets tot fase 7 van het plan"
mkdir -p "$HOME/PROJECTS/DRIVE-BACKUP"
date > "$HOME/PROJECTS/DRIVE-BACKUP/backup-PAUSED"
echo "NOODHERSTEL-OUDE-MAC" > "$HOME/PROJECTS/DRIVE-BACKUP/machine-id"

cat <<'EOF'

================================================================
 KLAAR MET VOORBEREIDEN. Open een NIEUW terminalvenster en start:   claude

 Zeg dan tegen Claude:

   Mijn MacBook is weg. Voer het noodherstel uit.
   Het plan staat in ~/NOODHERSTEL/HERSTEL-PLAN.md.
   Werk het van boven naar beneden af. Nooit rclone sync.

 Laatste geslaagde backup op de oude Mac:
EOF
date -r "$(cat "$HOME/NOODHERSTEL/last-success.txt" 2>/dev/null || echo 0)" 2>/dev/null | sed 's/^/   /'
echo "================================================================"
