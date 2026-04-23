# sokhatsky.art genealogical archiving project

This guide explains the data organization and metadata formats used in the sokhatsky.art genealogical project. The system uses an isomorphic storage approach, where a single large GEDCOM file (sokhatsky.ged) is exploded into a modular file system for easier editing and static site generation.

## Global Metadata

These files represent the "global" state of the family tree and are used for cross-referencing and reports.

### families.csv	

A master lookup table for all family units (marriages/partnerships). CSV: Id, Husb, Wife, Children. IDs are stripped of @ symbols.

### raw-FAM-F*.ged	

Preserves the exact GEDCOM syntax for each family record. GEDCOM: Text block starting with 0 @F... @ FAM.

### raw-SOUR-S*.ged

Preserves the exact GEDCOM syntax for each source/citation.	GEDCOM: Text block starting with 0 @S... @ SOUR.

### header.ged

Stores the original GEDCOM file header.	GEDCOM: Includes version, character encoding (UTF-8), and source system.

### sources.csv

A human-readable master list of all bibliographic sources. CSV: Id, Title, Text.

### familysearch.csv

The main report used for global indexing and relationship mapping. CSV: Includes Id, Depth (generation level), Color (lineage indicator), and Fully Qualified Name.

## Person Metainfo

Each individual is stored in a dedicated folder under priv/storage/, named as ID-GivenName-SURNAME (e.g., I501016-Calistratus-SOCHACKI).

### bio (bio-ID.txt)

Intent: Stores the narrative biography or descriptive notes.
Source: Extracted from GEDCOM NOTE, CONT, and CONC tags.
Format: Plain text. During a "repack," this file's content is used to rebuild the NOTE block in the final GEDCOM.

### events (events-ID.csv)

Intent: Captures specific life events beyond birth/death (e.g., Occupations, Residences, Military Service).
Format: .csv: Structural data with headers Tag, Value, Date, Place.

### indi (indi-ID.csv)

Intent: The primary "identity card" of the person.
Format: A Key-Value CSV (Field, Value). It stores the standard attributes like Given Name, Surname, Sex, Born Date, and Birth  Place.

### raw (raw-ID.ged)

Intent: The "Source of Truth" snippet.
Format: The exact, unmodified lines from the original .ged file for this individual. This ensures that even if the parser doesn't "understand" a custom tag, the data is preserved for the "repack" utility.

### csv (ID.csv)

Intent: A person-specific ancestry report.
Format: A CSV containing a list of all ancestors for this specific person up to 12 generations deep. It includes the Color coding used to style the lineage flags in the UI (e.g., Blue for paternal-paternal, Red for maternal-maternal).

## Summary

### Parse

`parse_sokhatsky.rb` reads the GEDCOM and creates these modular files.

### Edit

You can edit the bio-ID.txt or indi-ID.csv directly in the file system.

### Generate

`genie_sokhatsky.rb` reads these CSVs/text files to render the premium static HTML pages.

### Repack

`genie_sokhatsky.rb -g out.ged` merges all modular files back into a single valid GEDCOM file,
incorporating any manual edits you made to the text/CSV files.
