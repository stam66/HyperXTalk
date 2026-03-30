script "com.livecode.pi.combobox.behavior"
constant kEffectiveTextColor = "100,100,100"
constant kConflictedFieldColor = "193,201,215"
constant kDropdownButtonWidth = 18

# A combo box editor combines an editable text field (left) with a
# pulldown dropdown button (right). The user can either type a value
# directly into the field, or pick one from the dropdown list of
# predefined options.

on editorInitialize
   set the editorMinWidth of me to 60
   set the editorMaxWidth of me to 0

   # Dynamically create the pulldown button alongside the text field
   lock messages
   create button "pulldown" in me
   set the style of button "pulldown" of me to "menu"
   set the menumode of button "pulldown" of me to "pulldown"
   set the showborder of button "pulldown" of me to false
   set the showname of button "pulldown" of me to true
   set the label of button "pulldown" of me to "▾"
   set the textalign of button "pulldown" of me to "center"
   unlock messages

   # Populate the dropdown with the editor's predefined options
   local tOptions
   put the editorOptions of me into tOptions
   set the itemdelimiter to "|"
   local tMenuText
   repeat for each line tLine in tOptions
      -- Use only the display label (first item), strip value alias
      put item 1 of tLine & return after tMenuText
   end repeat
   delete the last char of tMenuText
   set the text of button "pulldown" of me to tMenuText

   editorResize
end editorInitialize

on editorUpdate
   lock screen
   local tValue, tEffective, tEnabled, tConflicted
   put the editorValue of me into tValue
   put the editorEnabled of me into tEnabled
   put the editorEffective of me into tEffective
   put the editorConflicted of me into tConflicted

   lock messages
   set the locktext of field 1 of me to not tEnabled
   set the enabled of button "pulldown" of me to tEnabled

   if tEffective is true then
      if the focusedobject is not the long ID of field 1 of me then
         put tValue into field 1 of me
      end if
      set the textcolor of field 1 of me to kEffectiveTextColor
      set the textstyle["italic"] of field 1 of me to true
   else
      put tValue into field 1 of me
      set the textstyle of field 1 of me to empty
      if not tEnabled then
         set the textcolor of field 1 of me to "108,108,108"
      else
         set the textcolor of field 1 of me to empty
      end if
   end if

   if tConflicted then
      set the backcolor of field 1 of me to kConflictedFieldColor
   else
      set the backcolor of field 1 of me to empty
   end if
   unlock messages

   unlock screen
end editorUpdate

on editorResize
   lock screen
   lock messages
   local tWidth, tHeight, tLeft, tTop
   put the width of me into tWidth
   put the height of me into tHeight
   put the left of me into tLeft
   put the top of me into tTop

   -- Text field occupies the left portion
   set the topleft of field 1 of me to tLeft, tTop
   set the width of field 1 of me to tWidth - kDropdownButtonWidth
   set the height of field 1 of me to the formattedHeight of field 1 of me

   -- Dropdown button is flush against the right edge
   set the top of button "pulldown" of me to tTop
   set the right of button "pulldown" of me to tLeft + tWidth
   set the width of button "pulldown" of me to kDropdownButtonWidth
   set the height of button "pulldown" of me to tHeight
   unlock messages
   unlock screen
end editorResize

# --- Text field handlers ---

on openField
   if the editorEffective of me is true then
      lock messages
      put empty into field 1 of me
      set the textcolor of field 1 of me to empty
      unlock messages
   end if
end openField

on exitField
   editorUpdate
end exitField

on returnInField
   valueChangedFromField
end returnInField

on enterInField
   valueChangedFromField
end enterInField

on closeField
   valueChangedFromField
end closeField

private command valueChangedFromField
   set the editorValue of me to field 1 of me
   updateProperty
end valueChangedFromField

# --- Dropdown button handler ---
# Called when the user picks an option from the pulldown menu.
on menuPick pItemName
   local tOptions, tValue
   put the editorOptions of me into tOptions
   set the itemdelimiter to "|"
   # Match the chosen display label back to its underlying value
   set the wholematches to false
   repeat for each line tLine in tOptions
      if item 1 of tLine is pItemName then
         put the last item of tLine into tValue
         exit repeat
      end if
   end repeat
   if tValue is empty then put pItemName into tValue
   put tValue into field 1 of me
   set the editorValue of me to tValue
   updateProperty
end menuPick
