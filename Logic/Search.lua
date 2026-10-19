local ADDON, ns = ...

-- Search over every mount (the Journal front page's search box). Pure Lua,
-- no WoW API: the caller passes each mount's searchable text as fields.
--
-- A query is split into words (lower case; letters, digits and any non-ASCII
-- byte, so accented names stay whole; apostrophes dropped on both sides, so
-- "ahnqiraj" finds "Ahn'Qiraj"). Filler words (of, the, ...) are ignored
-- unless the query is nothing else. Each remaining word is scored against
-- every field of a mount, keeping its best field:
--   3    the word equals a field word, or an abbreviation (ALIASES) whose
--        phrase is in the field ("cata", "icc", "bfa"),
--   2    a field word starts with it ("rai" -> "raider"),
--   1.5  it is inside a field word (3+ letters),
--   1    a typo: within 1 edit of a field word (4-5 letters) or 2 edits
--        (6+), counting a swap of two neighbours as one edit.
-- Mount-name matches weigh 1.3x. A mount is a result when every word
-- matches (one or two words) or at least two thirds of them do (three or
-- more: "flirty of the raider cata" still finds the Cataclysm raider
-- mounts through "raider" and "cata"). The whole query appearing in a field
-- adds a bonus.
-- Results are grouped by why they matched: the field that scored most
-- (Search.FIELDS order breaks ties) is the section "search_<field>".
-- Groups come best match first; inside a group by words matched, score,
-- then name.

local Search = {}
ns.Search = Search

-- Field kinds in tie-break order.
Search.FIELDS = { "name", "boss", "instance", "zone", "achievement", "expansion", "other" }
local FIELD_RANK = {}
for i, f in ipairs(Search.FIELDS) do FIELD_RANK[f] = i end
local WEIGHT = { name = 1.3 }

local STOP = {
  ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["and"] = true,
  ["to"] = true, ["in"] = true, ["on"] = true, ["for"] = true,
}

-- Abbreviation -> the words it stands for (matched as a phrase).
Search.ALIASES = {
  bc = "burning crusade", tbc = "burning crusade",
  wrath = "wrath of the lich king", wotlk = "wrath of the lich king", wotl = "wrath of the lich king",
  cata = "cataclysm",
  mop = "mists of pandaria",
  wod = "warlords of draenor",
  bfa = "battle for azeroth",
  sl = "shadowlands",
  df = "dragonflight",
  tww = "the war within",
  icc = "icecrown citadel",
  toc = "trial of the crusader", totc = "trial of the crusader",
  aq = "ahnqiraj",
  bwl = "blackwing lair",
  mc = "molten core",
  zg = "zulgurub",
  za = "zulaman",
  ssc = "serpentshrine cavern",
  tk = "tempest keep",
  bt = "black temple",
  tot = "throne of thunder",
  hfc = "hellfire citadel",
  brf = "blackrock foundry",
  tos = "tomb of sargeras",
  abt = "antorus the burning throne",
  bod = "battle of dazaralor",
  cn = "castle nathria",
  sod = "sanctum of domination",
  sfo = "sepulcher of the first ones",
  voti = "vault of the incarnates",
  atdh = "amirdrassil the dreams hope",
}

-- Lower-case words of `text`: runs of letters, digits and non-ASCII bytes,
-- apostrophes removed first.
function Search.Words(text)
  local out = {}
  if type(text) ~= "string" then return out end
  text = string.lower(text)
  text = string.gsub(text, "['`]", "")
  text = string.gsub(text, "\226\128\153", "") -- right single quote
  for word in string.gmatch(text, "[%w\128-\255]+") do out[#out + 1] = word end
  return out
end

-- Edit distance between a and b (insert, delete, substitute, swap of two
-- neighbours), or max + 1 once it is certain to exceed max.
function Search.Distance(a, b, max)
  local la, lb = #a, #b
  if math.abs(la - lb) > max then return max + 1 end
  local prev2, prev, cur = nil, {}, nil
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    cur = { [0] = i }
    local best = i
    local ca = string.byte(a, i)
    for j = 1, lb do
      local cb = string.byte(b, j)
      local cost = (ca == cb) and 0 or 1
      local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if prev2 and i > 1 and j > 1 and ca == string.byte(b, j - 1) and string.byte(a, i - 1) == cb then
        v = math.min(v, prev2[j - 2] + 1)
      end
      cur[j] = v
      if v < best then best = v end
    end
    if best > max then return max + 1 end
    prev2, prev = prev, cur
  end
  return prev[lb]
end

local function maxEdits(n)
  if n >= 6 then return 2 end
  if n >= 4 then return 1 end
  return 0
end

-- Prepared field: { words = { ... }, text = " w1 w2 ... " }.
local function prepare(text)
  local words = Search.Words(text)
  return { words = words, text = " " .. table.concat(words, " ") .. " " }
end

-- fields: { [kind] = string | { strings } } -> { [kind] = prepared }.
function Search.Prepare(fields)
  local out = {}
  for kind, value in pairs(fields or {}) do
    if FIELD_RANK[kind] then
      if type(value) == "table" then value = table.concat(value, " ") end
      if type(value) == "string" and value ~= "" then out[kind] = prepare(value) end
    end
  end
  return out
end

-- Score of query word `word` against one field word (0: no match).
local function pairScore(word, fw)
  if fw == word then return 3 end
  if #fw > #word and string.sub(fw, 1, #word) == word then return 2 end
  if #word >= 3 and string.find(fw, word, 1, true) then return 1.5 end
  local edits = maxEdits(#word)
  if edits > 0 and Search.Distance(word, fw, edits) <= edits then return 1 end
  return 0
end

-- Score of one query word against one prepared field (0: no match).
-- memo (optional): { [field word] = score } for this query word, shared
-- across mounts; field words repeat a lot, so each is scored once.
function Search.WordScore(word, field, memo)
  local alias = Search.ALIASES[word]
  if alias and string.find(field.text, " " .. alias .. " ", 1, true) then return 3 end
  local best = 0
  for _, fw in ipairs(field.words) do
    local s = memo and memo[fw]
    if not s then
      s = pairScore(word, fw)
      if memo then memo[fw] = s end
    end
    if s > best then
      best = s
      if best == 3 then return 3 end
    end
  end
  return best
end

-- The query's words: { words = { ... }, phrase = " w1 w2 " } (filler words
-- dropped unless that leaves none), or nil for a query under two letters.
function Search.Query(text)
  local all = Search.Words(text)
  if #all == 0 or #table.concat(all) < 2 then return nil end
  local words = {}
  for _, w in ipairs(all) do
    if not STOP[w] then words[#words + 1] = w end
  end
  if #words == 0 then words = all end
  return { words = words, phrase = " " .. table.concat(all, " ") .. " ", all = all }
end

-- How many of n words must match.
function Search.Needed(n)
  if n <= 2 then return n end
  return math.ceil(n * 2 / 3)
end

-- One mount: prepared fields, parsed query -> nil, or { matched =, score =,
-- field = } (the field that scored most).
function Search.Match(prepared, query)
  local matched, total = 0, 0
  local byField = {}
  query.memo = query.memo or {}
  for _, word in ipairs(query.words) do
    local memo = query.memo[word]
    if not memo then
      memo = {}
      query.memo[word] = memo
    end
    local bestScore, bestField = 0, nil
    for kind, field in pairs(prepared) do
      local s = Search.WordScore(word, field, memo) * (WEIGHT[kind] or 1)
      if s > bestScore or (s == bestScore and s > 0 and FIELD_RANK[kind] < FIELD_RANK[bestField]) then
        bestScore, bestField = s, kind
      end
    end
    if bestField then
      matched = matched + 1
      total = total + bestScore
      byField[bestField] = (byField[bestField] or 0) + bestScore
    end
  end
  if matched < Search.Needed(#query.words) then return nil end
  if #query.all > 1 then
    for kind, field in pairs(prepared) do
      if string.find(field.text, query.phrase, 1, true) then
        local bonus = 4 * (WEIGHT[kind] or 1)
        total = total + bonus
        byField[kind] = (byField[kind] or 0) + bonus
      end
    end
  end
  local field, fieldScore = nil, -1
  for kind, s in pairs(byField) do
    if s > fieldScore or (s == fieldScore and FIELD_RANK[kind] < FIELD_RANK[field]) then
      field, fieldScore = kind, s
    end
  end
  return { matched = matched, score = total, field = field }
end

-- query: { search =, fields = fn(id, m) -> fields (Search.Prepare input),
-- gate = fn(id, m) -> owned boolean | nil (excluded), cache = {} (optional:
-- prepared fields by mount ID, reused across calls) }.
-- -> list of { id =, m =, section = "search_<field>", matched =, score = },
-- grouped and ordered as described at the top.
function Search.Select(mounts, query)
  local parsed = Search.Query(query.search)
  if not parsed then return {} end
  local cache = query.cache or {}
  local hits = {}
  for id, m in pairs(mounts or {}) do
    if query.gate == nil or query.gate(id, m) ~= nil then
      local prepared = cache[id]
      if not prepared then
        prepared = Search.Prepare(query.fields and query.fields(id, m) or { name = m.name })
        cache[id] = prepared
      end
      local hit = Search.Match(prepared, parsed)
      if hit then
        hit.id, hit.m, hit.section = id, m, "search_" .. hit.field
        hits[#hits + 1] = hit
      end
    end
  end

  local function better(a, b)
    if a.matched ~= b.matched then return a.matched > b.matched end
    if a.score ~= b.score then return a.score > b.score end
    return nil
  end
  -- Each group ranks by its best hit.
  local top = {}
  for _, h in ipairs(hits) do
    local t = top[h.section]
    if not t or better(h, t) then top[h.section] = h end
  end
  table.sort(hits, function(a, b)
    if a.section ~= b.section then
      local ta, tb = top[a.section], top[b.section]
      local o = better(ta, tb)
      if o ~= nil then return o end
      return FIELD_RANK[ta.field] < FIELD_RANK[tb.field]
    end
    local o = better(a, b)
    if o ~= nil then return o end
    local na, nb = string.lower(a.m.name or ""), string.lower(b.m.name or "")
    if na ~= nb then return na < nb end
    return a.id < b.id
  end)
  return hits
end
