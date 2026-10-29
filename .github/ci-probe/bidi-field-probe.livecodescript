script "bidiFieldProbe"
/*
CI probe for upstream PR 564 / issue 563: on Windows, after pasting
">>> FSI PDI PDI <<<" (U+2068 U+2069 U+2069) into a field, typing stops
working. This stack is run by the Windows CI job with the freshly built
Debug standalone engine. It logs everything to the file named by $BIDI_LOG
and writes PNG snapshots next to it, then quits.
*/

local sLog

private command log pText
   put pText & return after sLog
   put sLog into URL ("file:" & $BIDI_LOG)
end log

private function fieldState pLabel
   local tOut
   put pLabel & ":" & return into tOut
   put "  text=[" & the text of fld "f" of stack "bidiTest" & "]" & return after tOut
   put "  codepoints=" & codepointsOf(the text of fld "f" of stack "bidiTest") & return after tOut
   put "  length=" & the number of codepoints of the text of fld "f" of stack "bidiTest" & return after tOut
   put "  selectedChunk=" & the selectedChunk & return after tOut
   put "  focusedObject=" & the focusedObject & return after tOut
   put "  formattedWidth=" & the formattedWidth of fld "f" of stack "bidiTest" & return after tOut
   put "  formattedHeight=" & the formattedHeight of fld "f" of stack "bidiTest" & return after tOut
   put "  formattedRect of line 1=" & the formattedRect of line 1 of fld "f" of stack "bidiTest" & return after tOut
   put "  textDirection resolved via the formattedText=" & codepointsOf(the formattedText of fld "f" of stack "bidiTest") after tOut
   return tOut
end fieldState

private function codepointsOf pText
   local tOut, tCP
   repeat for each codepoint tCP in pText
      put "U+" & baseConvert(codepointToNum(tCP), 10, 16) & space after tOut
   end repeat
   return tOut
end codepointsOf

private command snapshot pName
   local tFile
   put $BIDI_LOG into tFile
   set the itemDelimiter to "."
   put pName & ".png" into the last item of tFile
   try
      export snapshot from fld "f" of stack "bidiTest" to file tFile as PNG
      log "snapshot" && pName && "written:" && tFile && "(" & the result & ")"
   catch tErr
      log "snapshot" && pName && "FAILED:" && tErr
   end try
end snapshot

on startup
   local tIso, tStr, tStart

   log "probe start" && the internet date
   log "engine version" && the version && "build" && the buildNumber
   log "platform" && the platform && the systemVersion
   log "log file" && $BIDI_LOG

   put numToCodepoint(0x2068) & numToCodepoint(0x2069) & numToCodepoint(0x2069) into tIso
   put ">>> " & tIso & " <<<" into tStr

   -- A visible stack with one editable field, like a user's test stack.
   create stack "bidiTest"
   set the rect of stack "bidiTest" to "100,100,520,320"
   set the defaultStack to "bidiTest"
   create field "f"
   set the rect of fld "f" of stack "bidiTest" to "10,10,400,120"
   set the textFont of fld "f" of stack "bidiTest" to "Segoe UI"
   set the textSize of fld "f" of stack "bidiTest" to 13
   go stack "bidiTest"
   wait 1 second with messages
   log "stack opened, window id" && the windowID of stack "bidiTest" && "mode" && the mode of stack "bidiTest"

   -- Phase A: typing in a clean field, first via the engine's own key path
   -- (the 'type' command goes through MCStack::kdown -> MCField::kdown ->
   -- finsertnew exactly like a WM_CHAR would once it leaves the Win32 layer),
   -- then by leaving the window idle so the CI wrapper can SendKeys "abc"
   -- through the real Win32 message loop.
   focus on fld "f" of stack "bidiTest"
   select after text of fld "f" of stack "bidiTest"
   type "123"
   log fieldState("A1 after type 123 (engine path)")
   log "A2 waiting 12s for external keys (expect abc)"
   wait 12 seconds with messages
   log fieldState("A2 after external keys")

   -- Phase B: paste the issue string through the real clipboard/paste path
   -- (MCDispatch::dopaste -> MCClipboard::CopyAsParagraphs -> pastetext).
   select after text of fld "f" of stack "bidiTest"
   set the clipboardData["text"] to tStr
   log "clipboardData text codepoints=" & codepointsOf(the clipboardData["text"])
   paste
   log "paste result=[" & the result & "]"
   log fieldState("B1 after paste")
   snapshot "after-paste"

   -- Phase C: type after the paste, engine path first.
   type "456"
   log fieldState("C1 after type 456 (engine path)")
   snapshot "after-type"
   log "C2 waiting 15s for external keys (expect xyz)"
   wait 15 seconds with messages
   log fieldState("C2 after external keys")
   snapshot "after-external-keys"

   -- Phase D: click into the field (hit-testing through GetCursorIndex) and
   -- type again, then try a fresh field in the same stack.
   click at (the right of fld "f" of stack "bidiTest" - 20, the top of fld "f" of stack "bidiTest" + 12)
   type "789"
   log fieldState("D1 after click + type 789")

   create field "g"
   set the rect of fld "g" of stack "bidiTest" to "10,130,400,190"
   focus on fld "g" of stack "bidiTest"
   type "fresh"
   log "D2 fresh field g text=[" & the text of fld "g" of stack "bidiTest" & "]"

   -- Phase E: the same string set directly, then typed into.
   set the text of fld "g" of stack "bidiTest" to tStr
   select after text of fld "g" of stack "bidiTest"
   type "end"
   log "E1 field g after set text + type end=[" & the text of fld "g" of stack "bidiTest" & "]"

   log "probe end" && the internet date
   quit
end startup
