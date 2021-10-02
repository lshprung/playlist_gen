## Introduction

A set of Perl scripts to help automate the creation of audio playlists. This repository contains two scripts:

- `build_db.plx` - Generate a sqlite3 database for your audio library, including each file's metadata tags
- `build_playlists.plx` - Generate m3u playlist files based on the sqlite3 database generated by `build_db.plx`

For usage of these scripts, append the `--help` flag

### Example

To build a database of all audio files in your `$HOME/Music` directory, and save the database as `$HOME/Music/library.db`:

```
./build_db.plx
```

To create a set of m3u playlists for every album in the database, and output all the m3u files in `$HOME/Music/playlists`:

```
./build_playlists.plx ALBUM,ALBUMARTIST "$HOME/Music/playlists/{ALBUMARTIST} - {ALBUM}.m3u"
```

To create an m3u playlist of all files in the database where the 'ARTIST' tag is 'Steely Dan', and save it as `steely_dan.m3u` in the current working directory:

```
./build_playlists.plx --sql "ARTIST='Steely Dan';" steely_dan.m3u
```
