/* Copyright (C) 2015 LiveCode Ltd.
 
 This file is part of LiveCode.
 
 LiveCode is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License v3 as published by the Free
 Software Foundation.
 
 LiveCode is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or
 FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 for more details.
 
 You should have received a copy of the GNU General Public License
 along with LiveCode.  If not see <http://www.gnu.org/licenses/>.  */

#include <core.h>

#include "libbrowser_internal.h"

extern bool MCWKWebViewBrowserFactoryCreate(MCBrowserFactoryRef &r_factory);
extern bool MCWebViewBrowserFactoryCreate(MCBrowserFactoryRef &r_factory);

// WKWebView is the primary factory on macOS — avoids the main-thread
// process-launch stall caused by the deprecated WebView class.
// The legacy "WebView" entry is kept so that scripts explicitly requesting
// it continue to work.
MCBrowserFactoryMap kMCBrowserFactoryMap[] =
{
	{ "WkWebView", nil, MCWKWebViewBrowserFactoryCreate },
	{ "WebView",   nil, MCWebViewBrowserFactoryCreate   },
	{ nil,         nil, nil                              },
};

MCBrowserFactoryMap* s_factory_list = kMCBrowserFactoryMap;

