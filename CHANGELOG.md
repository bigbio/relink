# bigbio/relink: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

