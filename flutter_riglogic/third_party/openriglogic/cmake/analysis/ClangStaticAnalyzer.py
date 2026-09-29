#-*- coding: utf-8 -*-
import argparse
import json
import subprocess
import sys

ANALYZER_ARGS = [
    '--analyze',
    '-Xclang', '-analyzer-opt-analyze-nested-blocks',
    '-Xclang', '-analyzer-config', '-Xclang', 'aggressive-binary-operation-simplification=true',
    '-Xclang', '-analyzer-output=text'
]


def run_analyzer(compile_commands_path, exclude_dirs, include_dirs):
    try:
        with open(compile_commands_path, 'r') as ccfile:
            ccdb = json.load(ccfile)
    except Exception as exc:
        print(f"Error opening compilation database at: {compile_commands_path}")
        return True

    warned = False

    for tu in ccdb:
        if exclude_dirs and any(tu['file'].startswith(dir) for dir in exclude_dirs):
            continue

        if include_dirs and not any(tu['file'].startswith(dir) for dir in include_dirs):
            continue

        cmdline = tu['command'].split(' ')
        try:
            output_index = cmdline.index('-o')
        except ValueError:
            # No output parameter, nothing to remove
            pass
        else:
            # Delete '-o /path/to/objfile.o' part since analysis produces no output
            del cmdline[output_index:output_index + 2]

        cmdline += ANALYZER_ARGS
        proc = subprocess.Popen([' '.join(cmdline)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True, encoding='utf-8')
        (stdout, stderr) = proc.communicate()

        if stdout:
            warned = True
            print(stdout)

        if stderr:
            warned = True
            print(stderr)

    return warned


def main():
    parser = argparse.ArgumentParser(description="Clang Static Analyzer")
    parser.add_argument('--compilation-database',
                        dest='compilation_database',
                        required=True,
                        help='Path to compile_commands.json file (compilation database)')
    parser.add_argument('--exclude-dir',
                        dest='exclude_dirs',
                        nargs='*',
                        help='Directory to exclude while processing compilation database')
    parser.add_argument('--include-dir',
                        dest='include_dirs',
                        nargs='*',
                        help='Directory to include while processing compilation database')
    args = parser.parse_args()
    warned = run_analyzer(args.compilation_database, args.exclude_dirs or [], args.include_dirs or [])
    if warned:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
