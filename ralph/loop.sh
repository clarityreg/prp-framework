#!/bin/bash
# Ralph Wiggum Loop - Autonomous AI Development
# Based on ghuntley/how-to-ralph-wiggum implementation
#
# Usage:
#   ./loop.sh [max_iterations]         - Run unified mode (RECOMMENDED - implement + test + verify)
#   ./loop.sh                          - Run unified mode indefinitely
#   ./loop.sh plan [max_iterations]    - Run planning mode (gap analysis only)
#   ./loop.sh verify [max_iterations]  - Run verify mode (visual testing & compliance)
#   ./loop.sh build [max_iterations]   - Run build mode (implementation only - LEGACY)
#   ./loop.sh qa [max_iterations]      - Run QA mode (test generation & coverage improvement)
#
# Examples:
#   ./loop.sh            # Run unified mode indefinitely (RECOMMENDED)
#   ./loop.sh 10         # Run 10 unified iterations
#   ./loop.sh plan 5     # Run 5 planning iterations
#   ./loop.sh verify 3   # Run 3 verification iterations
#   ./loop.sh build 10   # Run 10 build-only iterations (legacy)
#   ./loop.sh qa 5       # Run 5 QA iterations (test generation)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Determine mode and max iterations
if [ "$1" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}  # 0 = infinite
    echo "Running in PLANNING mode"
elif [ "$1" = "verify" ]; then
    MODE="verify"
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_verify.md"
    MAX_ITERATIONS=${2:-0}  # 0 = infinite
    echo "Running in VERIFY mode (visual testing & compliance)"
elif [ "$1" = "build" ]; then
    # Legacy build-only mode
    MODE="build"
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_build.md"
    MAX_ITERATIONS=${2:-0}  # 0 = infinite
    echo "Running in BUILD mode (legacy - consider using unified mode)"
elif [ "$1" = "qa" ]; then
    MODE="qa"
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_qa.md"
    MAX_ITERATIONS=${2:-0}  # 0 = infinite
    echo "Running in QA mode (test generation & coverage improvement)"
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    # Number = unified mode with max iterations
    MODE="unified"
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_unified.md"
    MAX_ITERATIONS=$1
    echo "Running in UNIFIED mode (implement + test + verify) with max $MAX_ITERATIONS iterations"
else
    # Default = unified mode indefinitely
    MODE="unified"
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_unified.md"
    MAX_ITERATIONS=0  # infinite
    echo "Running in UNIFIED mode (implement + test + verify) indefinitely"
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "Working on branch: $CURRENT_BRANCH"

ITERATION=0
START_TIME=$(date +%s)

# Main loop - each iteration is a FRESH context
while true; do
    ITERATION=$((ITERATION + 1))
    ITER_START=$(date +%s)

    echo ""
    echo "============================================"
    echo "ITERATION $ITERATION - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Mode: $MODE"
    echo "============================================"

    # Check max iterations
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -gt $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Run Claude with fresh context each time
    # The prompt file contains all instructions - progress is in IMPLEMENTATION_PLAN.md
    cat "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose \
        2>&1 | tee "$SCRIPT_DIR/logs/iteration_${ITERATION}.log" || {
            echo "Claude exited with error, continuing..."
        }

    # Auto-push changes after each iteration
    if git diff --quiet && git diff --staged --quiet; then
        echo "No changes to push"
    else
        echo "Pushing changes..."
        git push origin "$CURRENT_BRANCH" 2>/dev/null || {
            echo "Creating remote branch..."
            git push -u origin "$CURRENT_BRANCH"
        }
    fi

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))
    echo "Iteration $ITERATION completed in ${ITER_DURATION}s"

    # Brief pause between iterations
    sleep 2
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
echo ""
echo "============================================"
echo "Loop completed after $ITERATION iterations"
echo "Total time: ${TOTAL_DURATION}s"
echo "============================================"
