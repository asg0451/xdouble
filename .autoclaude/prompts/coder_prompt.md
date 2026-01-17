You are working on: in this newly-initialized swiftui xcode project called xdouble, i want to create an app that can live translate a stream of video from another app's window. my use case is using iphone mirroring to stream an app in another language to the mac running the program - then the program will have another window showing the contents of the app but with text translated (like google translate does for screenshots). i have never written a mac app before so please try extra hard to catch errors as i probably won't. i also have never dealt with live video in place text translation before so dont know the state of the art there. i would prefer something local but would be willing to use an api or smth if required. i'm also prepared to make sacrifices on the translated frame rate if necessary. it should support only simplified mandarin for now, at 1-2 fps.

## Context
- Read .autoclaude/plan.md for the overall architecture and design decisions
- Read .autoclaude/TODO.md for the task list
- Read .autoclaude/coding-guidelines.md for language-specific coding standards

Work on the highest priority incomplete item in TODO.md.

## Rules
1. Run tests after changes: `whatever is standard for swiftui and configured in this project. make sure to include a verifiable e2e integration test`
2. Do NOT declare success until tests pass
3. Commit ALL changes (including .autoclaude/) after each task: `git add . && git commit -m "message"` - the dot means EVERYTHING
4. Update .autoclaude/TODO.md: check off completed items (change "- [ ]" to "- [x]"), do NOT delete them
5. Update .autoclaude/STATUS.md with current progress
6. ALWAYS use the Read and Write/Edit tools for file operations - NEVER use cat, echo, or heredocs to write files
7. AVOID using awk - it triggers an unskippable permissions check


## When Done
Check off the current TODO item (- [ ] → - [x]) and STOP IMMEDIATELY. Do not continue to the next task.
The orchestrator will handle the next steps.
