#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vidura-reproducibility-regression.XXXXXX")"
HARNESS="${BUILD_DIR}/reproducibility_regression"

cleanup() {
  rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

xcrun swiftc \
  "${REPO_ROOT}/Physics Companion/Pathutils.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/AgentTypes.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/CodegenAgent.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/ChartModels.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/OpenAIClient.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/PhysicsReviewerAgent.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/RunnerSummaryParser.swift" \
  "${REPO_ROOT}/Physics Companion/Agents/RunnerService.swift" \
  "${REPO_ROOT}/Physics Companion/HEPReferences.swift" \
  "${REPO_ROOT}/Physics Companion/RunLineageResolver.swift" \
  "${REPO_ROOT}/Physics Companion/RunQualityAnalyzer.swift" \
  "${REPO_ROOT}/script/reproducibility_regression/main.swift" \
  -o "${HARNESS}"

"${HARNESS}"
