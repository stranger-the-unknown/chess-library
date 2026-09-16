# Chess Library

***English** · [Türkçe](README.tr.md)*

An app for reading chess games, solving puzzles, studying openings and
playing against an engine that runs **entirely on your device**. No
internet connection is needed; no data ever leaves the device.

Runs on **Android** and **Windows**. The interface adapts to the window
width: a bottom navigation bar on a phone, a rail down the left side on
the desktop.

Languages: Turkish and English. Change it in Settings; the default is
your system language.

---

## Play

**Play the engine** — Pick one of six levels, from beginner to master;
each level says briefly how often it errs. Your colour can be white,
black or **random**. You can also start from a **position you set up
yourself** instead of the standard arrangement.

**Load PGN** — From a file, or by pasting from the clipboard. A file may
hold any number of games: they are listed, and you save the ones you pick
as a **new list** or **add them to an existing list**. Headers, comments,
variations, NAG marks and games that begin with a `[FEN]` tag are all
read. Long files show a progress bar and the app stays responsive.

**Free board** — An analysis board where you play both sides.

**Set up a position** — A full position editor with a piece palette, side
to move, castling rights and the en passant square. You can type into the
FEN field directly or paste one from the clipboard. Analyse the position
you built or play the engine from it; the menu can save the board as a
PNG.

---

## The board screen

Move a piece by dragging it, or by tapping the piece and then the target
square. When a pawn promotes you are asked which piece you want.

**Engine analysis** — Opens from the chart icon in the top right. You get
an evaluation bar, an arrow for the best move, the main line and the
search depth. The analysis runs on a separate thread, so the board stays
smooth.

**Navigation** — Tap any move in the move strip to go to that position;
the buttons below step back and forward, or jump to the start or the end.

**Marks and arrows (mouse)** — **Right-click** a square to mark it;
**hold the right button and drag** to draw an arrow between two squares.
Right-clicking the same place again removes the mark, a left click clears
them all. The colour is derived from the board you chose, so the marks
stay visible on every style.

**Trial moves** — While looking at a saved game you can play any move on
the board to see how the engine's evaluation changes. These moves are not
written into the game: they do not appear in the move list, they are not
exported to PGN, they are not saved, and they disappear when you leave
the screen. The buttons on the strip undo the last trial move or take you
back to the game.

**Game review** — When a game ends the engine scores every move. You get
an accuracy percentage per side, a quality for each move (best / very
good / good / inaccuracy / mistake / blunder), an evaluation chart and a
list of the turning points. Tap the chart to jump between moves.

The menu also offers: copy PGN, copy and paste FEN, save to a list, flip
the board and **resign**.

**Sounds** — Different sounds for different kinds of move (your move, the
opponent's move, a capture, castling, promotion, check). The illegal-move
warning is heard only when you are **in check**, where it means "this
move does not get you out of check". Tapping an invalid square at any
other time is silent.

---

## Puzzles

The app ships with no puzzles; you build the lists yourself.

**Creating a list** — The **+** in the top right opens a new list. While
naming it you can also mark it as an **endgame list**, which turns on the
outcome filters described below; this can be changed later from the list
menu. There are three ways to fill a list:

1. **One at a time** — "Add puzzle" in the menu, then set the position up
   on the board.
2. **Paste a FEN list** — "Add a FEN list" in the menu, one FEN per line.
3. **Import from a text file** — "Import from text file" in the menu,
   then pick a `.txt`.

**File format** — One FEN per line. All three spellings are recognised:

```
7k/8/5K2/8/8/8/8/6Q1 w - - 0 1
12	7k/8/5K2/8/8/8/8/6Q1 w - - 0 1
7k/8/5K2/8/8/8/8/6Q1 w - - 0 1|mate-1,few-pieces|g1g7|12
```

That is: the FEN on its own, or `number<TAB>FEN`, or
`FEN|tags|solution|number`. Lines starting with `#` and blank lines are
skipped. Positions that break the rules of chess are dropped quietly.
Files with thousands of lines show a progress bar.

**Exporting** — "Export as text file" in the menu. The list is written as
`FEN|tags|solution|order` and reads back into the same app exactly as it
was. Use it as a backup or to move a list to another device.

**Solving** — Play the winning move on the board. Where a puzzle has a
recorded solution that line is used; where it does not, the engine judges
your move: if it does not drop the evaluation noticeably compared with
the best move it counts as correct, so an equally good alternative is
accepted. After a correct move the engine plays the reply.

You can ask for a hint, watch the solution, start over, add the puzzle to
favorites, mark it solved and write a note.

**Numbers** — A puzzle's number is its **real place in the list** (or the
number given in the source file). The same number is shown whatever
filter is active and whichever way the list is sorted; in the row, in the
puzzle title and in the information line above it.

**Sorting** — The list is in list order, the same as in the book it came
from. The arrow in the title bar reverses it and brings the newest to the
top. Changing a filter puts the order back: a reversed order is usually
wanted for one quick look, and that look is over once the filter changes.

**Search and filters** — All / unsolved / solved / favorites. If the list
is marked as an endgame list you also get **white wins / draw / black
wins** filters; an outcome is set from the row menu or comes from a tag
in an imported file (`white-wins`, `draw`, `black-wins`; the Turkish
spellings are recognised too).

The search box works on the number (`#128`), the tags, the name, the note
and the FEN, and ignores Turkish accents.

**Marking a range** — "Mark a range" in the menu sets every puzzle
between two numbers to solved or unsolved at once. The numbers are
independent of the filter: you type the number you see on screen.

**Daily count** — How many puzzles you have solved since midnight is
shown on the list cards on the puzzle lists screen. It can be turned off
in Settings.

The menu can also **save the board as a PNG**; the file is named
`board-<list name>-<number>.png`. Every puzzle can be renamed, its
position edited, its note deleted, or the puzzle removed entirely.

---

## Openings

The list starts empty; you add the lines you want to study.

**Adding a line** — A family name (for example "Ruy Lopez"), a variation
name (for example "Breyer Variation") and the moves, which can be pasted
as SAN or PGN. Every move is checked against the rules and you are warned
about one that does not fit. Lines are grouped by family: type the same
family name again and the new line joins that title. Leave the variation
name empty and it takes the next number in that family.

**Editing** — The name, family and moves of a line you added can be
changed from the row menu, its note deleted, or the line removed.

**Deleting a title** — The menu next to an opening title deletes every
line under it at once and tells you how many will go. When you have
imported hundreds of lines from a file, deleting them one by one is no
use. The progress and notes of the deleted lines are cleared too.

**Hiding** — The **hidden openings** screen in the title menu takes
titles you are not working on out of the list; only what you study stays
on the main screen, and nothing is deleted. The eye at the end of a row
hides that one title. The checkboxes are for selecting: pick a few titles
and **hide all but the selected** leaves only those, while **show all but
the selected** does the opposite. With nothing selected the same two
commands become *hide all* and *show all*. Hiding is tied to the family
name, not to an internal id, so it survives re-importing the same file.

**Expand and collapse** — **Expand all titles** and **collapse all
titles** in the title menu open or close every family at once. Searching
does not open titles by itself.

**Deleting everything** — **Delete all openings** in the title menu
removes the lines along with your progress and your notes. It cannot be
undone and asks how many lines will go.

**Reset all data** — Under Settings → Data, written in red. It deletes
every list, puzzle, opening, all progress and all settings, and asks for
confirmation; it cannot be undone. Android brings old data back from
Drive when you uninstall and reinstall the app, so this is the way to
start from scratch.

**Text file** — The opening list is exported and imported from the title
menu. Importing the same file a second time skips move sequences that are
already in the list, so nothing is duplicated; you are told how many were
skipped. Two lines that reach the same position by a different move order
count as different lines. One line per row:

```
C95|Ruy Lopez|Breyer Variation|1. e4 e5 2. Nf3 Nc6 3. Bb5 a6
Ruy Lopez|Breyer Variation|1. e4 e5 2. Nf3 Nc6 3. Bb5 a6
```

That is `ECO|family|variation|moves`, or the same three fields without
the ECO code.

**Watch** — Step through the line by hand or let it play itself.

**Practice** — You play the moves and are warned when one is wrong. Two
clean runs mark the line as learned.

Every line also offers a hint, a note, a favorite mark, "play the engine
from here" and "open in the analysis board".

---

## My lists

Your games are kept in folders: rename them, move games between them,
delete them.

- **Import a PGN file** adds many games to a list at once.
- **Export as a PGN file** writes the whole list out.
- Games in a list are numbered; search works on the number (`#42`), the
  game name, the players, the result and your note.
- **Read marks**: one at a time, all at once, or by giving a **range of
  numbers**; there is an unread / read filter. The number you have read
  is shown on the card without opening the list.
- **Favorites**: set with the star on a row, with a filter of their own.
- **Sorting** is reversed with the arrow in the title bar and goes back
  to the default when the filter changes.
- **Show a range** narrows the list to a stretch of numbers and is closed
  again from the banner at the top.
- The card shows both player names in full, and the date from the PGN if
  there is one (the year alone if the date is incomplete, nothing if
  there is no year).
- **Game details** in the row menu shows the PGN tags: event, site,
  round, ECO code, ratings.
- Games can carry a note, which can be deleted later.

### Batch analysis

Choose **select games to analyse** from the title menu and the rows
become selectable. Pick the ones you want and start either **quick** or
**deep** analysis; the games are worked through one after another while
you do something else. The screen stays awake while it runs, so a charger
is a good idea. Progress appears above the lists tab and can be cancelled
from there.

Each game is saved as it finishes. If the app closes half-way, the
finished ones stay; only the rest are left undone.

### Analysis lists

At the top of the lists there are two of them: **Recent Deep Analyses**
and **Recent Quick Analyses**. Each keeps at most a hundred records,
newest first, and the oldest drops off beyond that.

These two belong to the app rather than to you: they cannot be deleted or
renamed, and neither can the records inside them be renamed, deleted,
moved to another list or marked read in bulk; PGN cannot be imported into
them either. Read and favorite marks, search, filters, sorting, showing a
range, game details and copying PGN all work.

Opening a saved analysis does not run the engine again. Analysing the
same game a second time does not delete the old record, it adds a new one
— the list is a history.

Marking an analysis record as read or favorite also marks the original
game. It does not work the other way round: a game can have several
analyses, so there would be no telling which one to update.

Analysis records are **not included in backups**; they belong to the
device and can be produced again. "Reset all data" does delete them.

---

## Backups and moving to a new device

**Settings → Data → Back up all data** writes everything the app keeps
into a single `.json` file: your game lists and the games in them (read
marks, favorites, notes), your puzzle lists and progress (solved,
favorite, attempts, the date solved), the openings you added and your
progress through them, and all of your settings.

The file is plain text and contains nothing platform-specific; a backup
taken on a phone opens on a PC and the other way round.

**Settings → Data → Restore from backup** asks for the file. What is
inside it is summarised first — how many lists, games, puzzles and
openings — so you notice a wrong file before any data is deleted. Then
you are offered two modes:

- **Merge** — The backup is added on top of what is here. Where the same
  record exists on both sides the one from the backup wins, and the
  settings on this device are left alone.
- **Replace** — The data on this device is deleted and the backup takes
  its place. It is for making two devices identical, and asks for an
  extra confirmation.

A checksum is written into the file, so a backup that downloaded
half-way or was damaged is caught before it is loaded. If something goes
wrong while writing, the old data is put back.

---

## Settings

- **Theme** — dark, light or follow the system. Default: follows the
  system.
- **Language** — system, Turkish, English.
- **Board style** — 32 choices:
  - **12 flat colours** (brown, green, tournament, blue, grey, slate,
    sand, purple, ivory, rose, teal, midnight) — no image file, drawn
    directly, sharp at any size.
  - **3 wood boards** (dark wood, walnut, oak) — made for this project.
  - **17 textures**: four woods, two maples, marble, blue marble, stone,
    metal, leather, canvas, olive, green plastic, pink pyramid, purple
    stripe and horsey.
- **Piece set** — 16 choices: Cburnett (default), Chessnut, RhosGFX,
  Fantasy, Spatial, Celtic, Kiwen Suwi, Firi, Totoy, Papercut, Merida,
  Mono, Letter, Pirouetti, Pixel, MPChess.
- **Show square names** — the coordinate colour comes from the board you
  chose: the text takes the opposite colour of the square it sits on. On
  boards whose two square colours are close to each other, such as stone
  and marble, the contrast is measured and the text falls back to black
  or white so it does not disappear.
- Legal move hints, last move highlight, move animation, evaluation bar.
- **Daily solved count** — shows the daily counter on puzzle list cards.
- **Move sounds** and **vibration** — vibration exists only on the phone;
  turning sounds off turns vibration off too, and it cannot be turned on
  again until sounds are back on.
- **Data** — backup and restore (see above).

The board and piece set you choose are used not only on the game board
but also in the small previews in puzzle and game lists.

---

## Installing

**Android** — Copy the APK to the phone and open it. You may need to
allow installation from unknown sources.

**Windows** — Run `Chess Library <version> Kurulum.exe`. It does not ask
for administrator rights and installs into your own user folder; it adds
a Start menu shortcut and can be removed from the Control Panel.

If you would rather not install anything, use the portable version: copy
**the whole** folder you were given and run `ChessLibrary.exe` inside it.
The app will not start without the DLLs and the `data` folder next to it.

> Windows may show a "Windows protected your PC" warning the first time:
> the app is not signed with a code signing certificate. Get past it with
> **More info → Run anyway**.

---

## Licence

The project is licensed under [AGPLv3](LICENSE): it is free software,
anyone may sell it and anyone may modify it — but everyone who receives
the app must also be able to get the source code, and modified versions
must be distributed under the same licence. The reasoning and the details
are in [COPYRIGHT.md](COPYRIGHT.md).

The piece sets come from elsewhere; see [ASSETS.md](ASSETS.md) for the
artists and their licences.

---

To build from source see [BUILD.md](BUILD.md); for how the sounds and
images were produced see [ASSETS.md](ASSETS.md). Those two documents, and
`COPYRIGHT.md`, are written in Turkish.

A user manual is published with each release as a PDF, in English and in
Turkish.
