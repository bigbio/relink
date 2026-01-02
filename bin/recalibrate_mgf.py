#!/usr/bin/env python3
"""
Recalibrate MGF files based on mass errors calculated from xiSEARCH linear search results.

This script:
1. Reads xiSEARCH linear search results and peak annotations
2. Calculates precursor (MS1) and fragment (MS2) mass errors
3. Recalibrates the MGF file by applying the calculated corrections
4. Optionally generates mass error distribution plots
"""

import argparse
import sys
from pathlib import Path
from typing import NamedTuple

import polars as pl
from pyopenms import MascotGenericFile, MSExperiment


class MassError(NamedTuple):
    """Container for precursor and MS2 mass errors in ppm."""

    precursor_error: float
    ms2_error: float


def calculate_mass_error(
    linear_results_path: Path,
    peaks_path: Path,
    minimum_match_score: float = 6.0,
    minimum_precursor_count: int = 50,
    ms2_error_bounds: tuple[float, float] = (30.0, -30.0),
) -> MassError:
    """
    Calculate precursor and MS2 mass errors from xiSEARCH linear search results.

    Args:
        linear_results_path: Path to xiSEARCH linear search CSV output
        peaks_path: Path to xiSEARCH peaks TSV output
        minimum_match_score: Minimum match score to consider a PSM
        minimum_precursor_count: Minimum number of precursors for recalibration
        ms2_error_bounds: Upper and lower bounds for MS2 error filtering

    Returns:
        MassError with precursor and MS2 error in ppm
    """
    # Load and filter xiSEARCH results
    xi_df = (
        pl.read_csv(linear_results_path, infer_schema=False)
        .with_columns(pl.col("decoy").str.replace_all(",", "").cast(pl.Int64))
        .with_columns(pl.col("match score").str.replace_all(",", "").cast(pl.Float64))
        .filter((pl.col("decoy") == 0) & (pl.col("match score") > minimum_match_score))
        .with_columns(pl.col("Scan").str.replace_all(",", "").cast(pl.Int64))
        .with_columns(pl.col("Run").replace("", None).cast(pl.Int64))
        .with_columns(
            pl.col("Precursor Error").str.replace_all(",", "").cast(pl.Float64)
        )
    )

    # Load peaks data
    peaks_df = (
        pl.read_csv(
            peaks_path,
            separator="\t",
            truncate_ragged_lines=True,
            infer_schema=False,
        )
        .with_columns(pl.col("CalcMZ").str.replace_all(",", "").cast(pl.Float64))
        .with_columns(pl.col("MS2Error").str.replace_all(",", "").cast(pl.Float64))
        .with_columns(pl.col("ScanNumber").str.replace_all(",", "").cast(pl.Int64))
        .with_columns(pl.col("Run").replace("", None).cast(pl.Int64))
        .with_columns(pl.col("IsPrimaryMatch").str.replace_all(",", "").cast(pl.Int64))
    )

    # Extract precursor errors
    precursor_error_df = xi_df.select(pl.col("Precursor Error"))

    # Check if we have enough data points
    if len(precursor_error_df) < minimum_precursor_count:
        print(
            f"Warning: Only {len(precursor_error_df)} precursors found, below threshold of {minimum_precursor_count}. Skipping recalibration.",
            file=sys.stderr,
        )
        return MassError(0.0, 0.0)

    # Calculate MS1 (precursor) error
    precursor_error = precursor_error_df.median().item()

    # Calculate MS2 error
    ms2_error_df = (
        peaks_df.filter(pl.col("IsPrimaryMatch") == 1)
        .join(
            xi_df.select(pl.col("Scan", "Run", "decoy")),
            left_on=["ScanNumber", "Run"],
            right_on=["Scan", "Run"],
            how="inner",
            nulls_equal=True,
        )
        .with_columns(MS2Error_ppm=((pl.col("MS2Error") * 10.0**6) / pl.col("CalcMZ")))
        .filter(
            (pl.col("MS2Error_ppm") <= ms2_error_bounds[0])
            & (pl.col("MS2Error_ppm") >= ms2_error_bounds[1])
        )
        .select(pl.col("MS2Error_ppm"))
    )

    ms2_error = ms2_error_df.median().item() if len(ms2_error_df) > 0 else 0.0

    return MassError(precursor_error, ms2_error), precursor_error_df, ms2_error_df


def recalibrate_mgf(
    mgf_path: Path,
    output_path: Path,
    mass_error: MassError,
) -> None:
    """
    Apply mass recalibration to an MGF file.

    Args:
        mgf_path: Path to input MGF file
        output_path: Path to write recalibrated MGF
        mass_error: MassError with precursor and MS2 corrections in ppm
    """
    exp = MSExperiment()
    MascotGenericFile().load(str(mgf_path), exp)

    recalibrated_spectra = []
    for spectrum in exp:
        # Recalibrate precursor mass
        precursors = spectrum.getPrecursors()
        for precursor in precursors:
            corrected_mz = precursor.getMZ() / (
                1 + mass_error.precursor_error / 10.0**6
            )
            precursor.setMZ(corrected_mz)
        spectrum.setPrecursors(precursors)

        # Recalibrate MS2 peak masses
        mz_array, intensity_array = spectrum.get_peaks()
        corrected_mz_array = mz_array / (1 + mass_error.ms2_error / 10.0**6)
        spectrum.set_peaks((corrected_mz_array, intensity_array))

        recalibrated_spectra.append(spectrum)

    exp.setSpectra(recalibrated_spectra)
    MascotGenericFile().store(str(output_path), exp)


def generate_plots(
    prefix: str,
    precursor_error_df: pl.DataFrame,
    precursor_error: float,
    ms2_error_df: pl.DataFrame | None,
    ms2_error: float,
) -> None:
    """
    Generate mass error distribution plots.

    Args:
        prefix: Prefix for output filenames
        precursor_error_df: DataFrame with precursor errors
        precursor_error: Calculated median precursor error
        ms2_error_df: DataFrame with MS2 errors (optional)
        ms2_error: Calculated median MS2 error
    """
    import matplotlib.pyplot as plt
    import seaborn as sns

    # Plot precursor error distribution
    if len(precursor_error_df) > 0:
        plt.figure(figsize=(10, 6))
        sns.histplot(precursor_error_df.to_pandas(), x="Precursor Error")
        plt.axvline(
            precursor_error,
            color="red",
            linestyle="--",
            label=f"Median: {precursor_error:.2f} ppm",
        )
        plt.title(
            f"MS1 Precursor Error Distribution\nMedian: {precursor_error:.2f} ppm"
        )
        plt.ylabel("# of Identifications")
        plt.xlabel("Precursor Error (ppm)")
        plt.legend()
        plt.tight_layout()
        plt.savefig(f"MS1_Error_{prefix}.png", dpi=150)
        plt.close()

    # Plot MS2 error distribution
    if ms2_error_df is not None and len(ms2_error_df) > 0:
        plt.figure(figsize=(10, 6))
        sns.histplot(ms2_error_df.to_pandas(), x="MS2Error_ppm")
        plt.axvline(
            ms2_error, color="red", linestyle="--", label=f"Median: {ms2_error:.2f} ppm"
        )
        plt.title(f"MS2 Fragment Ion Error Distribution\nMedian: {ms2_error:.2f} ppm")
        plt.ylabel("# of Identifications")
        plt.xlabel("Mass Error (ppm)")
        plt.xlim(-20, 20)
        plt.legend()
        plt.tight_layout()
        plt.savefig(f"MS2_Error_{prefix}.png", dpi=150)
        plt.close()


def main():
    parser = argparse.ArgumentParser(
        description="Recalibrate MGF files based on xiSEARCH linear search results"
    )
    parser.add_argument(
        "--linear-results",
        type=Path,
        required=True,
        help="Path to xiSEARCH linear search CSV results",
    )
    parser.add_argument(
        "--peaks",
        type=Path,
        required=True,
        help="Path to xiSEARCH peaks TSV file",
    )
    parser.add_argument(
        "--mgf",
        type=Path,
        required=True,
        help="Path to input MGF file",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Path to output recalibrated MGF file",
    )
    parser.add_argument(
        "--error-report",
        type=Path,
        required=True,
        help="Path to output mass error report CSV",
    )
    parser.add_argument(
        "--prefix",
        type=str,
        default="sample",
        help="Prefix for output files",
    )
    parser.add_argument(
        "--plot",
        action="store_true",
        help="Generate mass error distribution plots",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=6.0,
        help="Minimum match score threshold (default: 6.0)",
    )
    parser.add_argument(
        "--min-precursors",
        type=int,
        default=50,
        help="Minimum number of precursors for recalibration (default: 50)",
    )

    args = parser.parse_args()

    # Validate input files
    for path, name in [
        (args.linear_results, "linear results"),
        (args.peaks, "peaks"),
        (args.mgf, "MGF"),
    ]:
        if not path.exists():
            print(f"Error: {name} file not found: {path}", file=sys.stderr)
            sys.exit(1)

    # Calculate mass errors
    print(f"Calculating mass errors from {args.linear_results}...")
    result = calculate_mass_error(
        args.linear_results,
        args.peaks,
        minimum_match_score=args.min_score,
        minimum_precursor_count=args.min_precursors,
    )

    # Unpack results
    if isinstance(result, tuple) and len(result) == 3:
        mass_error, precursor_error_df, ms2_error_df = result
    else:
        mass_error = result
        precursor_error_df = None
        ms2_error_df = None

    print(f"Calculated mass errors:")
    print(f"  Precursor (MS1): {mass_error.precursor_error:.4f} ppm")
    print(f"  Fragment (MS2):  {mass_error.ms2_error:.4f} ppm")

    # Write error report
    error_report = pl.DataFrame(
        {
            "sample": [args.prefix],
            "precursor_error_ppm": [mass_error.precursor_error],
            "ms2_error_ppm": [mass_error.ms2_error],
        }
    )
    error_report.write_csv(args.error_report)
    print(f"Wrote error report to {args.error_report}")

    # Recalibrate MGF
    print(f"Recalibrating {args.mgf}...")
    recalibrate_mgf(args.mgf, args.output, mass_error)
    print(f"Wrote recalibrated MGF to {args.output}")

    # Generate plots if requested
    if args.plot and precursor_error_df is not None:
        print("Generating mass error plots...")
        generate_plots(
            args.prefix,
            precursor_error_df,
            mass_error.precursor_error,
            ms2_error_df,
            mass_error.ms2_error,
        )
        print("Plots generated successfully")

    print("Done!")


if __name__ == "__main__":
    main()
