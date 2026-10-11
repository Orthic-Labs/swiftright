"""Run measured factory workflow without automatic promotion."""
import argparse
import json
import sys
from .workflow import HERE, ROOT, prepare, collect, report, gate, queue, gate_evidence, font_addendum
from factory.core.artifacts import load_artifact, write_artifact
from .reader_config import load_origin_reader_config


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('prepare', 'collect', 'report', 'gate', 'gate-evidence', 'queue', 'font-addendum'):
        p = sub.add_parser(name)
        p.add_argument('--output', required=True)
        if name in ('prepare', 'gate', 'gate-evidence'):
            p.add_argument('--tuple', default=str(HERE / 'inputs/observed-tuple.json'))
        if name in ('prepare', 'report', 'gate', 'gate-evidence'):
            p.add_argument('--config', default=str(HERE / 'inputs/acceptance-candidate.json'))
        if name in ('collect', 'report', 'gate', 'gate-evidence'):
            p.add_argument('--cases', default=str(HERE / 'inputs/cases.json'))
            p.add_argument('--evidence-root', action='append', required=True)
        if name in ('collect', 'report', 'gate-evidence'):
            p.add_argument('--exclude-capture-dir', action='append', default=[], help='explicit superseded case directory inside selected root')
        if name in ('report', 'queue'):
            p.add_argument('--registry', default=str(ROOT / 'factory/registry/evidence/block-registry.json'))
        if name == 'prepare':
            p.add_argument('--seed', type=int, default=0)
            p.add_argument('--snapshot-created-at', help='explicit future snapshot timestamp; defaults to each recipe createdAt')
        if name == 'report':
            p.add_argument('--primaries', default=str(HERE / 'inputs/primary-cases.json'))
            p.add_argument('--demand', default=str(ROOT / 'factory/shell/demand.json'))
            p.add_argument('--compile-summary')
            p.add_argument('--corrections', default=str(HERE / 'corrections'))
            p.add_argument('--native-holds')
        if name in ('gate', 'gate-evidence'):
            p.add_argument('--manifests', default=str(HERE / 'manifests'))
            p.add_argument('--origin-reader-config', help='explicit archive roots for origin verification; omission keeps native origin held')
        if name == 'gate':
            p.add_argument('--test-seed', type=int, help='tests only; production chooses runtime seed')
        if name == 'gate-evidence':
            p.add_argument('--plan', required=True)
        if name == 'font-addendum':
            p.add_argument('--evidence-root', action='append', required=True)
            p.add_argument('--cases-dir', default=str(ROOT / 'factory/resources/fonts/pilot/cases'))
            p.add_argument('--resource', default=str(ROOT / 'factory/resources/fonts/resource.json'))
            p.add_argument('--private-collection', default=str(ROOT / 'factory/resources/fonts/windows/private-collection-result.json'))
            p.add_argument('--typecheck', default=str(ROOT / 'factory/native/windows/font-typecheck-20261010/typecheck-observation.json'))
            p.add_argument('--binding', default=str(ROOT / 'factory/resources/fonts/pilot/binding.json'))
    args = parser.parse_args(argv)
    try:
        origin_reader = load_origin_reader_config(args.origin_reader_config) if getattr(args, 'origin_reader_config', None) else None
        if args.command == 'prepare':
            result = prepare(args.output, args.tuple, args.config, args.seed, args.snapshot_created_at)
        elif args.command == 'collect':
            from .workflow import fresh_output
            out = fresh_output(args.output)
            result = collect(load_artifact(args.cases), args.evidence_root, args.exclude_capture_dir)
            write_artifact(out / 'collection.json', result)
        elif args.command == 'report':
            result = report(args.output, args.cases, args.evidence_root, args.primaries, args.config, args.registry, args.demand, args.compile_summary, args.corrections, args.native_holds, args.exclude_capture_dir)
        elif args.command == 'gate':
            result = gate(args.output, args.cases, args.evidence_root, args.tuple, args.config,
                          args.manifests, args.test_seed, origin_reader=origin_reader)
        elif args.command == 'gate-evidence':
            result = gate_evidence(args.output, args.plan, args.cases, args.evidence_root,
                args.tuple, args.config, args.manifests, args.exclude_capture_dir,
                origin_reader=origin_reader)
        elif args.command == 'font-addendum':
            result = font_addendum(args.output, args.evidence_root, args.cases_dir, args.resource, args.private_collection, args.typecheck, args.binding)
        else:
            result = queue(args.output, args.registry)
        print(json.dumps({k: result[k] for k in ('caseDenominator', 'primaryDenominator', 'nativeCaptureCount', 'nativeMacCaptureCount', 'nativeWindowsCaptureCount', 'status', 'seed', 'activation') if k in result}, sort_keys=True))
        return 3 if result.get('status') == 'blocked' else 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f'pipeline: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
