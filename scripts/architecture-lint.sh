#!/usr/bin/env bash
# Static architecture checks for CodingStandards.md's review rules that a compiler
# cannot enforce. Not shipped in the package (CodingStandards.md §4's allowance for
# one-off diagnostic scripts under scripts/). Run manually or wire into CI as a
# pre-merge gate; exits non-zero on any violation.
#
# Checks implemented (see CodingStandards.md §2/§4/§6/§7/§8 for the rules themselves):
#   1. Graph Engine facade rule — only OI_GraphEngine.cls may reference
#      OI_GraphBuilder/OI_GraphTraversal/OI_GraphRepository/OI_GraphSerializer/OI_GraphCache.
#   2. OI_GraphRepository/OI_GraphBuilder never construct inline SOQL/SOSL.
#   3. No literal 15/18-char Salesforce ID-shaped string constants in Apex.
#   4. No System.debug left in shipped Apex.
#   5. No empty catch blocks.
#
# What this script does NOT (and cannot) enforce — documented per CLAUDE.md's "if a
# violation cannot be automatically enforced, document the review rule" instruction:
#   - Controller thinness (permission check -> one Service call -> DTO map)
#   - Selector read-only-ness
#   - Cross-service Selector/Repository reach-through
#   - Container vs. presentational LWC split
#   These remain PR-review-time checks per CodingStandards.md §2/§10.

set -uo pipefail
CLASSES_DIR="force-app/main/default/classes"
VIOLATIONS=0

echo "== 1. Graph Engine facade rule =="
INTERNAL_NAMES="OI_GraphBuilder|OI_GraphTraversal|OI_GraphRepository|OI_GraphSerializer|OI_GraphCache"
while IFS= read -r -d '' file; do
    base=$(basename "$file")
    case "$base" in
        OI_GraphEngine.cls|OI_GraphBuilder.cls|OI_GraphTraversal.cls|OI_GraphRepository.cls|OI_GraphSerializer.cls|OI_GraphCache.cls) continue ;;
        *Test.cls|OI_Fake*.cls) continue ;; # test doubles/fakes are allowed to reference these for DI setup
    esac
    # Strip /** ... */ doc-comment blocks and // line comments before checking —
    # this rule is about actual code references, not architecture prose in ApexDoc
    # headers that legitimately name these classes as context.
    # Also strip single-quoted string literal contents — a class name mentioned inside
    # an exception message or a cache-key string constant is text, not a code reference.
    code_only=$(sed -e ':a;N;$!ba;s#/\*\*[^*]*\*\+\([^/*][^*]*\*\+\)*/##g' "$file" | grep -Ev '^\s*//' | sed -E "s/'[^']*'//g")
    if echo "$code_only" | grep -Eq "\\b($INTERNAL_NAMES)\\b"; then
        echo "  VIOLATION: $file references a Graph Engine internal component directly."
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done < <(find "$CLASSES_DIR" -name "*.cls" -print0)

echo "== 2. No inline SOQL/SOSL in OI_GraphRepository/OI_GraphBuilder =="
for f in "$CLASSES_DIR/OI_GraphRepository.cls" "$CLASSES_DIR/OI_GraphBuilder.cls"; do
    if [ -f "$f" ] && grep -Eq "\\[\\s*SELECT|\\[\\s*FIND" "$f"; then
        echo "  VIOLATION: $f contains inline SOQL/SOSL — must delegate to a Selector."
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

echo "== 3. No literal Salesforce-ID-shaped string constants =="
while IFS= read -r -d '' file; do
    if grep -EnHo "'[a-zA-Z0-9]{15}'|'[a-zA-Z0-9]{18}'" "$file" | grep -Ev "::v|checksum" >/dev/null; then
        grep -EnHo "'[a-zA-Z0-9]{15}'|'[a-zA-Z0-9]{18}'" "$file" | grep -Ev "::v|checksum" | while read -r hit; do
            echo "  VIOLATION: $file:$hit looks like a hardcoded Id literal."
        done
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done < <(find "$CLASSES_DIR" -name "*.cls" -print0)

echo "== 4. No System.debug in shipped Apex =="
while IFS= read -r -d '' file; do
    if grep -q "System.debug" "$file"; then
        echo "  VIOLATION: $file contains System.debug — use OI_LoggerService."
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done < <(find "$CLASSES_DIR" -name "*.cls" -print0)

echo "== 5. No empty catch blocks =="
while IFS= read -r -d '' file; do
    if grep -Pzoq "catch\s*\([^)]*\)\s*\{\s*\}" "$file" 2>/dev/null; then
        echo "  VIOLATION: $file contains an empty catch block."
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done < <(find "$CLASSES_DIR" -name "*.cls" -print0)

echo ""
if [ "$VIOLATIONS" -eq 0 ]; then
    echo "PASS: no architecture-lint violations found."
    exit 0
else
    echo "FAIL: $VIOLATIONS violation(s) found."
    exit 1
fi
