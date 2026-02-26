"""
Reformats numbers im MGF files to not use scientific notation.

This script:
1. Reads MGF files.
2. Reformats any found numbers in scientific notation into decimal notation.
"""

import argparse
import re
import sys
from pathlib import Path


def scientific_to_decimal(match: re.Match) -> str:
    """
    Converts a regex match of scientific notation to decimal notation.

    Args:
        match: Regex match object of a number in scientific notation

    Returns:
        Number string in decimal
    """
    return str(float(match.group(1)) * (10 ** int(match.group(3))))


def reformat_mgf(
    mgf: Path,
    output_file: Path,
) -> None:
    """
    Replaces instances of scientific notation with the decimal equivalent.

    Args:
        mgf: Path to input MGF file
        output_file: Path to write reformatted MGF
    """
    with mgf.open("r") as infile, output_file.open("w") as outfile:
        outfile.writelines(
            re.sub(r"(\d\.\d+)(e)(\d+)", scientific_to_decimal, line) for line in infile
        )


def main():
    parser = argparse.ArgumentParser(
        description="Reformats numbers in scientific notation to decimal"
    )
    parser.add_argument(
        "--mgf", type=Path, required=True, help="Path to input MGF file"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Path to output reformatted MGF file",
    )
    args = parser.parse_args()
    for path, name in [
        (args.mgf, "MGF"),
    ]:
        if not path.exists():
            print(f"Error: {name} file not found: {path}", file=sys.stderr)
            sys.exit(1)
    print(f"Reformatting {args.mgf}...")
    reformat_mgf(args.mgf, args.output)
    print(f"Wrote reformatted MGF to {args.output}")
    print("Done!")


if __name__ == "__main__":
    main()
