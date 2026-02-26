# bigbio/relink: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0dev - [2026-02-24]

### Added

- Test samples for test workflow
- Format Correction preprocessing to ensure scientific notation can be read by xiSEARCH

### Fixed

- Wrapped call to mass_recal.py with a call to python to fix failure to call it as an executable
- Reduced test samples to 1 to reduce runtime for Github actions
- Updated expected output and XIFDR arguments to reflect faulty argument parsing for file output names
- Updated output names in docs/output.md to reflect actual pipeline outputs

## v1.0.1dev - [2026-02-10]

### Fixed

- File path handling for pipeline parameter dump to JSON
- Added missing import of parameter logging function
- Added missing import of parameter validation function

## v1.0.0dev - [date]

Initial development release of bigbio/relink.

### Added

- File conversion from RAW to MGF using ThermoRawFileParser
- Linear peptide search using xiSEARCH for mass recalibration
- Mass recalibration of MGF files based on linear search results
- Crosslinking peptide search using xiSEARCH
- FDR correction using xiFDR
- MultiQC reporting with pMultiQC
- nf-core compliant pipeline structure
- Docker container with xiSEARCH 1.8.11, xiFDR 2.3.10, and Python dependencies
- GitHub Actions for CI/CD and linting
