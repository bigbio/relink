#!/usr/bin/env python3
"""Generate engine-specific config files from relink_config.tsv.

Reads the SDRF-derived relink_config.tsv and produces:
- xiSEARCH: xi_linear.conf + xi_crosslinking.conf
- Scout: search_params.json + filter_params.json
"""

import argparse
import json
import sys

import pandas as pd


def generate_xisearch_config(config_df: pd.DataFrame, output_prefix: str) -> None:
    """Generate xiSEARCH linear and crosslink config files."""
    row = config_df.iloc[0]

    enzyme = row.get("enzyme", "Trypsin")
    fixed_mods = row.get("fixed_modifications", "")
    variable_mods = row.get("variable_modifications", "")
    precursor_tol = row.get("precursor_mass_tolerance", "10 ppm")
    fragment_tol = row.get("fragment_mass_tolerance", "20 ppm")
    crosslinker_name = row.get("crosslinker_name", "DSSO")
    crosslinker_sites = row.get("crosslinker_sites", "K,S,T,Y,nterm")
    crosslinker_mass_heavy = row.get("crosslinker_mass_heavy", "54.01")
    crosslinker_mass_light = row.get("crosslinker_mass_light", "85.98")

    prec_val, prec_unit = _parse_tolerance(precursor_tol)
    frag_val, frag_unit = _parse_tolerance(fragment_tol)

    linear_config = (
        f"## xiSEARCH linear config (auto-generated from SDRF)\n"
        f"tolerance:precursor:{prec_val}{prec_unit}\n"
        f"tolerance:fragment:{frag_val}{frag_unit}\n"
        f"digestion:{enzyme}\n"
    )
    if fixed_mods:
        for mod in fixed_mods.split(";"):
            linear_config += f"modification:fixed:{mod.strip()}\n"
    if variable_mods:
        for mod in variable_mods.split(";"):
            linear_config += f"modification:variable:{mod.strip()}\n"

    with open(f"{output_prefix}_linear.conf", "w") as f:
        f.write(linear_config)

    crosslink_config = linear_config.replace("linear config", "crosslinking config")
    crosslink_config += (
        f"crosslinker:name:{crosslinker_name}\n"
        f"crosslinker:sites:{crosslinker_sites}\n"
        f"crosslinker:mass_heavy:{crosslinker_mass_heavy}\n"
        f"crosslinker:mass_light:{crosslinker_mass_light}\n"
    )

    with open(f"{output_prefix}_crosslinking.conf", "w") as f:
        f.write(crosslink_config)

    print(f"Generated xiSEARCH configs: {output_prefix}_linear.conf, {output_prefix}_crosslinking.conf")


def generate_scout_config(config_df: pd.DataFrame, output_prefix: str) -> None:
    """Generate Scout search and filter parameter JSON files."""
    row = config_df.iloc[0]

    enzyme = row.get("enzyme", "Trypsin")
    fixed_mods = row.get("fixed_modifications", "")
    variable_mods = row.get("variable_modifications", "")
    precursor_tol = row.get("precursor_mass_tolerance", "10 ppm")
    fragment_tol = row.get("fragment_mass_tolerance", "20 ppm")
    crosslinker_name = row.get("crosslinker_name", "DSSO")
    crosslinker_sites = row.get("crosslinker_sites", "K,S,T,Y,nterm")
    crosslinker_mass_heavy = row.get("crosslinker_mass_heavy", "54.01")
    crosslinker_mass_light = row.get("crosslinker_mass_light", "85.98")
    crosslinker_cleavable = row.get("crosslinker_cleavable", "yes")

    prec_val, prec_unit = _parse_tolerance(precursor_tol)
    frag_val, frag_unit = _parse_tolerance(fragment_tol)

    search_params = {
        "enzyme": enzyme,
        "fixed_modifications": [m.strip() for m in fixed_mods.split(";")] if fixed_mods else [],
        "variable_modifications": [m.strip() for m in variable_mods.split(";")] if variable_mods else [],
        "precursor_tolerance": {"value": float(prec_val), "unit": prec_unit},
        "fragment_tolerance": {"value": float(frag_val), "unit": frag_unit},
        "crosslinker": {
            "name": crosslinker_name,
            "reactive_sites": [s.strip() for s in str(crosslinker_sites).split(",")],
            "mass_heavy": float(crosslinker_mass_heavy) if crosslinker_mass_heavy else 0,
            "mass_light": float(crosslinker_mass_light) if crosslinker_mass_light else 0,
            "cleavable": str(crosslinker_cleavable).lower() == "yes",
        },
    }

    filter_params = {
        "fdr_threshold": 0.05,
        "level": "residue_pair",
    }

    with open(f"{output_prefix}_search_params.json", "w") as f:
        json.dump(search_params, f, indent=2)

    with open(f"{output_prefix}_filter_params.json", "w") as f:
        json.dump(filter_params, f, indent=2)

    print(f"Generated Scout configs: {output_prefix}_search_params.json, {output_prefix}_filter_params.json")


def _parse_tolerance(tol_str: str) -> tuple:
    """Parse tolerance string like '10 ppm' or '20 Da' into (value, unit)."""
    tol_str = str(tol_str).strip()
    parts = tol_str.split()
    if len(parts) >= 2:
        return parts[0], parts[1]
    return tol_str, "ppm"


def main():
    parser = argparse.ArgumentParser(description="Generate engine-specific configs from relink_config.tsv")
    parser.add_argument("--config", required=True, help="relink_config.tsv from SDRF parsing")
    parser.add_argument("--engine", required=True, choices=["xisearch", "scout"], help="Search engine")
    parser.add_argument("--output-prefix", default="generated", help="Output file prefix")
    parser.add_argument("--override", default=None, help="Optional user override config file")
    args = parser.parse_args()

    config_df = pd.read_csv(args.config, sep="\t")

    if args.engine == "xisearch":
        generate_xisearch_config(config_df, args.output_prefix)
    elif args.engine == "scout":
        generate_scout_config(config_df, args.output_prefix)


if __name__ == "__main__":
    main()
