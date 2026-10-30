script "bidiFieldProbe"
/*
CI probe for upstream PR 564 / issue 563: on Windows, after pasting
">>> FSI PDI PDI <<<" (U+2068 U+2069 U+2069) into a field, typing stops
working. The Windows CI job runs this stack with the freshly built Debug
standalone engine and with the Debug IDE engine. Everything is logged to
the file named by $BIDI_LOG; PNG snapshots are written next to it; marker
files ($BIDI_LOG & ".<phase>") tell the CI wrapper when to send keys
through the real Win32 message loop.
*/

local sLog, sRan

private command log pText
   put pText & return after sLog
   put sLog into URL ("file:" & $BIDI_LOG)
end log

private command marker pPhase
   put pPhase into URL ("file:" & $BIDI_LOG & "." & pPhase)
end marker

private function fieldState pLabel, pField
   local tOut
   put pLabel & ":" & return into tOut
   put "  text=[" & the text of pField & "]" & return after tOut
   put "  codepoints=" & codepointsOf(the text of pField) & return after tOut
   put "  length=" & the number of codepoints of the text of pField & return after tOut
   put "  selectedChunk=" & the selectedChunk & return after tOut
   put "  focusedObject=" & the focusedObject & return after tOut
   put "  tool=" & the tool & " defaultStack=" & the defaultStack & return after tOut
   put "  formattedWidth=" & the formattedWidth of pField & return after tOut
   put "  formattedHeight=" & the formattedHeight of pField & return after tOut
   put "  styledText blocks=" & the number of elements of the styledText of pField after tOut
   return tOut
end fieldState

private function codepointsOf pText
   local tOut, tCP
   repeat for each codepoint tCP in pText
      put "U+" & baseConvert(codepointToNum(tCP), 10, 16) & space after tOut
   end repeat
   return tOut
end codepointsOf

private command snapshot pName, pObject
   local tFile
   put $BIDI_LOG into tFile
   set the itemDelimiter to "."
   put pName & ".png" into the last item of tFile
   try
      export snapshot from fld (the short name of pObject) of stack "bidiTest" to file tFile as PNG
      log "snapshot" && pName && "written:" && tFile && "(" & the result & ")"
   catch tErr
      log "snapshot" && pName && "FAILED:" && tErr
   end try
end snapshot

private command typeInto pField, pText
   -- 'type' goes through MCStack::kdown -> MCField::kdown -> finsertnew, the
   -- same engine path a WM_CHAR takes once it leaves the Win32 layer.
   set the defaultStack to "bidiTest"
   choose browse tool
   focus on pField
   type pText
end typeInto

private command externalKeys pPhase, pField
   -- Ask the CI wrapper to send keys with SendKeys, then give the engine's
   -- own Win32 message loop time to receive them.
   log pPhase && "waiting 8s for external keys"
   set the defaultStack to "bidiTest"
   choose browse tool
   focus on pField
   marker pPhase
   wait 8 seconds with messages
end externalKeys

on startup
   runProbe "startup"
   pass startup
end startup

on openStack
   runProbe "openStack"
   pass openStack
end openStack

private command runProbe pEntry
   local tIso, tStr, tHtml, tF, tH, tK, tM

   if sRan then exit runProbe
   put true into sRan

   log "probe start" && the internet date && "entry" && pEntry
   log "engine version" && the version && "build" && the buildNumber && "environment" && the environment
   log "platform" && the platform && the systemVersion && "pixelScale" && the pixelScale

   -- Give the IDE (if we are running inside it) time to finish starting up.
   wait 5 seconds with messages

   put numToCodepoint(0x2068) & numToCodepoint(0x2069) & numToCodepoint(0x2069) into tIso
   put ">>> " & tIso & " <<<" into tStr

   create stack "bidiTest"
   set the rect of stack "bidiTest" to "100,100,560,420"
   set the defaultStack to "bidiTest"
   create field "f"
   put the long id of fld "f" of stack "bidiTest" into tF
   set the rect of tF to "10,10,440,80"
   set the textFont of tF to "Segoe UI"
   set the textSize of tF to 13
   create field "h"
   put the long id of fld "h" of stack "bidiTest" into tH
   set the rect of tH to "10,90,440,160"
   create field "k"
   put the long id of fld "k" of stack "bidiTest" into tK
   set the rect of tK to "10,170,440,240"
   set the textFont of tK to "Arial"
   create field "m"
   put the long id of fld "m" of stack "bidiTest" into tM
   set the rect of tM to "10,250,440,310"
   set the textFont of tM to "Microsoft Sans Serif"
   go stack "bidiTest"
   wait 1 second with messages
   log "stack opened, window id" && the windowID of stack "bidiTest" && "mode" && the mode of stack "bidiTest" && "tool" && the tool

   -- Phase A: typing into a clean field.
   typeInto tF, "123"
   log fieldState("A1 after type 123 (engine path)", tF)
   externalKeys "phaseA", tF
   log fieldState("A2 after external keys (expect abc)", tF)

   -- Phase B: paste the issue string as plain text through the real
   -- clipboard (MCDispatch::dopaste -> CopyAsParagraphs -> pastetext).
   set the defaultStack to "bidiTest"
   focus on tF
   select after text of tF
   set the clipboardData["text"] to tStr
   log "clipboardData text codepoints=" & codepointsOf(the clipboardData["text"])
   paste
   log "paste result=[" & the result & "]"
   log fieldState("B1 after plain-text paste", tF)
   snapshot "f-after-paste", tF

   -- Phase C: type after the paste.
   typeInto tF, "456"
   log fieldState("C1 after type 456 (engine path)", tF)
   externalKeys "phaseC", tF
   log fieldState("C2 after external keys (expect xyz)", tF)
   snapshot "f-after-typing", tF

   -- Phase D: click into the field (GetCursorIndex) and type again.
   click at (the right of tF - 20, the top of tF + 12)
   type "789"
   log fieldState("D1 after click + type 789", tF)

   -- Phase H: paste as HTML, the way a browser copy arrives on Windows
   -- (CF_HTML -> ConvertHTMLToStyledText -> styled paragraphs), into the
   -- field with the default font.
   put "<p>&gt;&gt;&gt; <code>" & tIso & "</code> &lt;&lt;&lt;</p>" into tHtml
   set the defaultStack to "bidiTest"
   choose browse tool
   focus on tH
   select after text of tH
   set the clipboardData["html"] to tHtml
   log "clipboardData keys after html set=" & the keys of the clipboardData
   log "clipboardData text now=[" & the clipboardData["text"] & "] codepoints=" & codepointsOf(the clipboardData["text"])
   paste
   log "html paste result=[" & the result & "]"
   log fieldState("H1 after html paste", tH)
   typeInto tH, "456"
   log fieldState("H2 after type 456 (engine path)", tH)
   externalKeys "phaseH", tH
   log fieldState("H3 after external keys (expect qrs)", tH)
   snapshot "h-after-html-paste-and-typing", tH

   -- Phase S: display scaling, as on a HiDPI Windows 11 laptop.
   try
      set the scaleFactor of stack "bidiTest" to 1.5
      wait 1 second with messages
      typeInto tF, "S"
      log fieldState("S1 scaleFactor 1.5, type S into f", tF)
      typeInto tH, "S"
      log fieldState("S2 scaleFactor 1.5, type S into h", tH)
      snapshot "f-scaled", tF
      set the scaleFactor of stack "bidiTest" to 1
   catch tErr
      log "S scaleFactor phase FAILED:" && tErr
   end try

   -- Phase F: other fonts, string set directly then typed into.
   set the text of tK to tStr
   select after text of tK
   typeInto tK, "end"
   log fieldState("F1 Arial after set text + type end", tK)
   set the text of tM to tStr
   select after text of tM
   typeInto tM, "end"
   log fieldState("F2 Microsoft Sans Serif after set text + type end", tM)

   -- Phase G: a fresh field after all that.
   create field "g"
   set the rect of fld "g" of stack "bidiTest" to "10,315,440,318"
   typeInto the long id of fld "g" of stack "bidiTest", "fresh"
   log "G1 fresh field g text=[" & the text of fld "g" of stack "bidiTest" & "]"

   log "probe end" && the internet date
   marker "done"
   -- The IDE may prompt to save; the CI wrapper kills the process if needed.
   set the cantModify of stack "bidiTest" to false
   quit
end runProbe
