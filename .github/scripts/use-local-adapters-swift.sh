#!/usr/bin/env bash
set -euo pipefail

# Wire swift-examples to a local adapters-swift checkout (PR branch / working tree).
#
# Usage:
#   use-local-adapters-swift.sh <adapters-swift-dir> <swift-examples-dir>
#
# Examples:
#   CI (sibling checkouts):
#     use-local-adapters-swift.sh "$GITHUB_WORKSPACE/adapters-swift" "$GITHUB_WORKSPACE/swift-examples"
#   Local clone nested in adapters-swift:
#     use-local-adapters-swift.sh "$(pwd)" "$(pwd)/swift-examples"

ADAPTERS_DIR="$(cd "${1:?adapters-swift directory}" && pwd)"
SWIFT_EXAMPLES_DIR="$(cd "${2:?swift-examples directory}" && pwd)"
PBXPROJ="${SWIFT_EXAMPLES_DIR}/examples-swift.xcodeproj/project.pbxproj"
CI_PACKAGE_SWIFT="${SWIFT_EXAMPLES_DIR}/dev/ci_examples/Package.swift"

if [[ ! -f "${ADAPTERS_DIR}/Package.swift" ]]; then
  echo "Local adapters-swift not found at: ${ADAPTERS_DIR}" >&2
  exit 1
fi

if [[ ! -f "${PBXPROJ}" ]]; then
  echo "Xcode project not found at: ${PBXPROJ}" >&2
  exit 1
fi

XCODE_REL="$(python3 - <<PY
import os
print(os.path.relpath("${ADAPTERS_DIR}", "${SWIFT_EXAMPLES_DIR}"))
PY
)"

python3 - "$PBXPROJ" "$XCODE_REL" <<'PY'
import re
import sys

path, rel = sys.argv[1:3]
text = open(path, encoding="utf-8").read()

remote_block = re.compile(
    r"/\* Begin XCRemoteSwiftPackageReference section \*/"
    r".*?"
    r"/\* End XCRemoteSwiftPackageReference section \*/",
    re.DOTALL,
)

local_block = f"""/* Begin XCLocalSwiftPackageReference section */
\t\tCE0678252DDDCBF300B73F2B /* XCLocalSwiftPackageReference "adapters-swift" */ = {{
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = {rel};
\t\t}};
\t\t/* End XCLocalSwiftPackageReference section */"""

text, count = remote_block.subn(local_block, text, count=1)
if count != 1:
    raise SystemExit(f"Expected to replace 1 remote package block, replaced {count}")

text = text.replace(
    'XCRemoteSwiftPackageReference "adapters-swift"',
    'XCLocalSwiftPackageReference "adapters-swift"',
)

if "testit-tms/adapters-swift" in text:
    raise SystemExit("Remote adapters-swift URL is still present in project.pbxproj")

open(path, "w", encoding="utf-8").write(text)
print(f"Patched Xcode project -> relativePath = {rel}")
PY

if [[ -f "${CI_PACKAGE_SWIFT}" ]]; then
  CI_REL="$(python3 - <<PY
import os
print(os.path.relpath("${ADAPTERS_DIR}", os.path.dirname("${CI_PACKAGE_SWIFT}")))
PY
)"

  python3 - "$CI_PACKAGE_SWIFT" "$CI_REL" <<'PY'
import re
import sys

path, rel = sys.argv[1:3]
text = open(path, encoding="utf-8").read()
pattern = r'\.package\(\s*url:\s*"https://github.com/testit-tms/adapters-swift"[^)]*\)'
replacement = f'.package(path: "{rel}")'
text, count = re.subn(pattern, replacement, text, count=1)
if count != 1:
    raise SystemExit(f"Expected to replace 1 Package.swift dependency, replaced {count}")
open(path, "w", encoding="utf-8").write(text)
print(f"Patched dev/ci_examples/Package.swift -> path = {rel}")
PY

  rm -f "${SWIFT_EXAMPLES_DIR}/dev/ci_examples/Package.resolved"
fi

RESOLVED_DIR="${PBXPROJ%/project.pbxproj}/project.xcworkspace/xcshareddata/swiftpm"
rm -rf "${RESOLVED_DIR}/Package.resolved" "${RESOLVED_DIR}/configuration"

echo "adapters-swift: ${ADAPTERS_DIR}"
echo "swift-examples: ${SWIFT_EXAMPLES_DIR}"
echo "xcode relativePath: ${XCODE_REL}"
