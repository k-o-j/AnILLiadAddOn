-- =============================================================================
-- SUNY Primo Search Addon for ILLiad
-- =============================================================================
-- Searches SUNY library holdings via Ex Libris Primo discovery.
-- When a staff member opens an ILL request, this addon can automatically
-- search Primo for the requested item by ISBN/ISSN or title.
--
-- Configurable for any SUNY campus by changing the settings in Config.xml:
--   PrimoBaseURL, PrimoVID, SearchScope, DefaultSearchField
--
-- Author: Karen Okamoto
-- Version: 1.0
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Settings (loaded from Config.xml)
-- ---------------------------------------------------------------------------
local settings = {};
settings.AutoSearch = GetSetting("AutoSearch");
settings.PrimoBaseURL = GetSetting("PrimoBaseURL");
settings.PrimoVID = GetSetting("PrimoVID");
settings.SearchScope = GetSetting("SearchScope");
settings.DefaultSearchField = GetSetting("DefaultSearchField");

-- ---------------------------------------------------------------------------
-- Interface variables
-- ---------------------------------------------------------------------------
local interfaceMngr = nil;

local SUNYPrimoForm = {};
SUNYPrimoForm.Form = nil;
SUNYPrimoForm.Browser = nil;
SUNYPrimoForm.RibbonPage = nil;

-- =============================================================================
-- Init() - Called when the addon loads
-- =============================================================================
-- Creates the addon tab with an embedded browser and ribbon toolbar buttons.
-- If AutoSearch is enabled, it automatically searches when the form opens.
-- =============================================================================
function Init()
    interfaceMngr = GetInterfaceManager();

    -- Create the addon tab in the ILLiad client
    SUNYPrimoForm.Form = interfaceMngr:CreateForm("SUNY Primo", "Script");

    -- Create the embedded browser that will display Primo search results
    SUNYPrimoForm.Browser = SUNYPrimoForm.Form:CreateBrowser(
        "SUNYPrimoBrowser",   -- internal name
        "SUNY Primo Search",  -- label shown to staff
        "SUNYPrimoSearch"     -- addon name reference
    );

    -- Hide the URL bar to keep the interface clean
    SUNYPrimoForm.Browser.TextVisible = false;

    -- Suppress JavaScript error popups from the Primo page
    SUNYPrimoForm.Browser.WebBrowser.ScriptErrorsSuppressed = true;

    -- Get the ribbon toolbar and add search buttons
    SUNYPrimoForm.RibbonPage = SUNYPrimoForm.Form:GetRibbonPage("SUNY Primo");

    -- "Search" button: tries ISBN/ISSN first, then falls back to title
    SUNYPrimoForm.RibbonPage:CreateButton(
        "Search",
        GetClientImage("Search32"),
        "Search",
        "SUNYPrimoSearch"
    );

    -- "Search Title" button: searches by title only
    SUNYPrimoForm.RibbonPage:CreateButton(
        "Search Title",
        GetClientImage("Search32"),
        "SearchTitle",
        "SUNYPrimoSearch"
    );

    -- "Search ISBN" button: searches by ISBN/ISSN only
    SUNYPrimoForm.RibbonPage:CreateButton(
        "Search ISBN",
        GetClientImage("Search32"),
        "SearchISBN",
        "SUNYPrimoSearch"
    );

    -- "Search Author" button: searches by author/creator
    SUNYPrimoForm.RibbonPage:CreateButton(
        "Search Author",
        GetClientImage("Search32"),
        "SearchAuthor",
        "SUNYPrimoSearch"
    );

    -- Show the addon tab
    SUNYPrimoForm.Form:Show();

    -- If AutoSearch is enabled, run a search immediately
    if settings.AutoSearch then
        Search();
    end
end

-- =============================================================================
-- URL Encoding
-- =============================================================================
-- Encodes special characters in a string so it can be safely used in a URL.
-- For example, spaces become %20, ampersands become %26, etc.
-- =============================================================================
function UrlEncode(str)
    if str == nil then
        return "";
    end

    -- Replace each non-alphanumeric character (except - _ . ~) with %XX
    str = string.gsub(str, "([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c));
    end);

    return str;
end

-- =============================================================================
-- BuildPrimoUrl(searchField, searchTerm)
-- =============================================================================
-- Constructs a full Primo deep link search URL.
--
-- Parameters:
--   searchField  - The Primo field to search (e.g. "title", "isbn", "any")
--   searchTerm   - The value to search for
--
-- Returns:
--   A complete URL string ready for browser navigation
--
-- Example output:
--   https://suny-pur.primo.exlibrisgroup.com/discovery/search
--     ?query=title,contains,criminal+justice
--     &tab=Everything
--     &search_scope=MyInst_and_CI
--     &vid=01SUNY_PUR:01SUNY_PUR
--     &mode=advanced
-- =============================================================================
function BuildPrimoUrl(searchField, searchTerm)
    local encodedTerm = UrlEncode(searchTerm);

    local url = settings.PrimoBaseURL
        .. "/discovery/search"
        .. "?query=" .. searchField .. ",contains," .. encodedTerm
        .. "&tab=Everything"
        .. "&search_scope=" .. settings.SearchScope
        .. "&vid=" .. settings.PrimoVID
        .. "&mode=advanced";

    return url;
end

-- =============================================================================
-- GetTitle() - Gets the item title from the current ILLiad transaction
-- =============================================================================
-- ILLiad stores titles in different fields depending on the request type:
--   Loan requests  -> "LoanTitle"
--   Article requests -> "PhotoJournalTitle"
-- =============================================================================
function GetTitle()
    local requestType = GetFieldValue("Transaction", "RequestType");

    if requestType == "Loan" then
        return GetFieldValue("Transaction", "LoanTitle");
    else
        return GetFieldValue("Transaction", "PhotoJournalTitle");
    end
end

-- =============================================================================
-- GetAuthor() - Gets the item author from the current ILLiad transaction
-- =============================================================================
-- ILLiad stores authors in different fields depending on the request type:
--   Loan requests  -> "LoanAuthor"
--   Article requests -> "PhotoArticleAuthor"
-- =============================================================================
function GetAuthor()
    local requestType = GetFieldValue("Transaction", "RequestType");

    if requestType == "Loan" then
        return GetFieldValue("Transaction", "LoanAuthor");
    else
        return GetFieldValue("Transaction", "PhotoArticleAuthor");
    end
end

-- =============================================================================
-- GetISxN() - Gets the ISBN or ISSN from the current ILLiad transaction
-- =============================================================================
-- The ISSN field in ILLiad is used for both ISBN and ISSN values.
-- =============================================================================
function GetISxN()
    return GetFieldValue("Transaction", "ISSN");
end

-- =============================================================================
-- Search() - Default search (ISBN/ISSN first, then title)
-- =============================================================================
-- This is the main search function called by the "Search" ribbon button
-- and by AutoSearch. It uses the best available identifier:
--   1. If an ISBN/ISSN exists, search by that (most precise)
--   2. Otherwise, fall back to searching by title
-- =============================================================================
function Search()
    local isxn = GetISxN();

    if isxn ~= nil and isxn ~= "" then
        -- ISBN/ISSN is available - use it for a precise search
        local url = BuildPrimoUrl("isbn", isxn);
        LogDebug("SUNY Primo Search: Searching by ISBN/ISSN: " .. isxn);
        SUNYPrimoForm.Browser:Navigate(url);
    else
        -- No ISBN/ISSN - fall back to title search
        local title = GetTitle();

        if title ~= nil and title ~= "" then
            local url = BuildPrimoUrl("title", title);
            LogDebug("SUNY Primo Search: Searching by title: " .. title);
            SUNYPrimoForm.Browser:Navigate(url);
        else
            LogDebug("SUNY Primo Search: No ISBN/ISSN or title available.");
            -- Navigate to Primo homepage so the staff can search manually
            SUNYPrimoForm.Browser:Navigate(
                settings.PrimoBaseURL
                .. "/discovery/search?vid=" .. settings.PrimoVID
            );
        end
    end
end

-- =============================================================================
-- SearchTitle() - Search by title only
-- =============================================================================
function SearchTitle()
    local title = GetTitle();

    if title ~= nil and title ~= "" then
        local url = BuildPrimoUrl("title", title);
        LogDebug("SUNY Primo Search: Searching by title: " .. title);
        SUNYPrimoForm.Browser:Navigate(url);
    else
        LogDebug("SUNY Primo Search: No title available for this request.");
    end
end

-- =============================================================================
-- SearchISBN() - Search by ISBN/ISSN only
-- =============================================================================
function SearchISBN()
    local isxn = GetISxN();

    if isxn ~= nil and isxn ~= "" then
        local url = BuildPrimoUrl("isbn", isxn);
        LogDebug("SUNY Primo Search: Searching by ISBN/ISSN: " .. isxn);
        SUNYPrimoForm.Browser:Navigate(url);
    else
        LogDebug("SUNY Primo Search: No ISBN/ISSN available for this request.");
    end
end

-- =============================================================================
-- SearchAuthor() - Search by author/creator
-- =============================================================================
function SearchAuthor()
    local author = GetAuthor();

    if author ~= nil and author ~= "" then
        local url = BuildPrimoUrl("creator", author);
        LogDebug("SUNY Primo Search: Searching by author: " .. author);
        SUNYPrimoForm.Browser:Navigate(url);
    else
        LogDebug("SUNY Primo Search: No author available for this request.");
    end
end
