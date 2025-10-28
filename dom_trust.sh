#!/usr/bin/env bash
# dom_trust.sh
# Print DNS -> NetBIOS mappings from ldapdomaindump domain_trusts.grep files.
# Usage:
#   ./dom_trust.sh -f path/to/domain_trusts.grep
#   ./dom_trust.sh --auto                        # process all */domaindump/domain_trusts.grep
#   ./dom_trust.sh -f -    # read from stdin
#   ./dom_trust.sh -f path -o out.txt
set -euo pipefail

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --file <path>     Input file to process. Use '-' to read from stdin.
  -a, --auto            Automatically find and process all */domaindump/domain_trusts.grep files.
  -o, --output <file>   Write output to file (appends). If omitted, prints to stdout.
  -h, --help            Show this help and exit.

Examples:
   Usage:
   ./dom_trust.sh -f path/to/domain_trusts.grep
   ./dom_trust.sh --auto                        # process all */domaindump/domain_trusts.grep
   ./dom_trust.sh -f -    # read from stdin
   ./dom_trust.sh -f path -o out.txt
EOF
}

# Parse args
INPUTS=()
OUTFILE=""
AUTO=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      shift
      if [[ -z "${1-}" ]]; then echo "Missing argument for --file"; exit 2; fi
      INPUTS+=("$1")
      shift
      ;;
    -a|--auto)
      AUTO=1
      shift
      ;;
    -o|--output)
      shift
      if [[ -z "${1-}" ]]; then echo "Missing argument for --output"; exit 2; fi
      OUTFILE="$1"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      exit 2
      ;;
  esac
done

# If --auto, gather all trust files
if [[ $AUTO -eq 1 ]]; then
  mapfile -t found < <(find . -maxdepth 3 -type f -path "*/domaindump/domain_trusts.grep" 2>/dev/null || true)
  if [[ ${#found[@]} -eq 0 ]]; then
    echo "No */domaindump/domain_trusts.grep files found under current directory." >&2
    exit 3
  fi
  for p in "${found[@]}"; do INPUTS+=("$p"); done
fi

if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "No input files provided. Use -f <file> or -a to auto-detect." >&2
  print_usage
  exit 2
fi

# Function that prints mapping for one file or stdin
process_file() {
  local f="$1"
  if [[ "$f" == "-" ]]; then
    # reading from stdin: print header-less mapping based on supplied lines
    awk -F'\t' 'NR==1{next} {printf "%-35s -> %s\n",$1,$2}' -
    return
  fi

  if [[ ! -f "$f" ]]; then
    echo "Skipping: file not found: $f" >&2
    return
  fi

  # If the file looks like it contains a header line, awk will skip it (NR==1{next})
  # We also prefix the block with the source file for clarity.
  echo "# from $f"
  awk -F'\t' 'NR==1{next} {printf "  %-35s -> %s\n",$1,$2}' "$f"
}

# Execute and capture output
if [[ -n "$OUTFILE" ]]; then
  # append to output file
  for inpath in "${INPUTS[@]}"; do
    # If reading from stdin and output file requested, we must read stdin once.
    if [[ "$inpath" == "-" ]]; then
      # read stdin into a temp file to allow writing to OUTFILE multiple times
      tmp=$(mktemp)
      cat - > "$tmp"
      process_file "$tmp" >> "$OUTFILE"
      rm -f "$tmp"
    else
      process_file "$inpath" >> "$OUTFILE"
    fi
  done
  echo "Wrote results to $OUTFILE"
else
  for inpath in "${INPUTS[@]}"; do
    if [[ "$inpath" == "-" ]]; then
      # read from stdin directly
      process_file "-"
    else
      process_file "$inpath"
    fi
  done
fi

exit 0
