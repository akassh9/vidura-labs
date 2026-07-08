#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vidura-hep-correctness-benchmark.XXXXXX")"
HARNESS="${BUILD_DIR}/hep_correctness_benchmark"

cleanup() {
  rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

xcrun swiftc \
  "${REPO_ROOT}/Physics Companion/Pathutils.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/AgentTypes.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/ChartModels.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/OpenAIClient.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/PhysicsReviewerAgent.swift" \
  "${REPO_ROOT}/Physics Companion/HEPReferences.swift" \
  "${REPO_ROOT}/Physics Companion/RunQualityAnalyzer.swift" \
  "${REPO_ROOT}/script/hep_correctness_benchmark/main.swift" \
  -o "${HARNESS}"

"${HARNESS}" \
  "${REPO_ROOT}/benchmarks/hep_correctness/tasks" \
  "${REPO_ROOT}/benchmark-results/hep_correctness"
