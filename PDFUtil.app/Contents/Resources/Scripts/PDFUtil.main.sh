#!/bin/bash
# PDFUtil.main.sh - Entry point for the PDFUtil applet
#
# The window is opened by NEXT_COMMAND_ID = PDFUtil.new; the object context
# (files dropped on the app icon) propagates to the chained command, and
# PDFUtil.init seeds the file list from OMC_OBJ_PATH.
#
# A non-blocking window's main command runs at an unpredictable time relative
# to the window appearing, so this stays empty on purpose - all initialization
# belongs in PDFUtil.init.
exit 0
