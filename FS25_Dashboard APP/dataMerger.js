// FS25 FarmDashboard | dataMerger.js | v2.0.0

/**
 * dataMerger.js  —  Merge Lua live data + XML savegame data
 *
 * Priority:
 *  Lua wins  → live animals, live weather/temperature, live vehicle engine state,
 *               field `needsWork` / PF overlay when a Lua row exists (XML heuristics are coarse)
 *  XML wins  → base field row from fields.xml (crop, growthState, soil flags),
 *               weather forecast, missions, farm statistics, game settings
 *  Merged    → vehicles (XML farmId/price + Lua engine/speed),
 *               economy (XML history + Lua sell points),
 *               farms (XML players/stats + Lua live money)
 *
 *  Field “Suggested Next Step” → when Lua has a row for that farmlandId, suggestions
 *  come from Lua only (live game). XML suggestions are used only when there is no Lua
 *  match (savegame-only / HTTP path). Never merge two suggestion lists.
 */

// ─── helpers ─────────────────────────────────────────────────────────────────

/** Lua serialises empty tables as {} — normalise to JS array */
function toArr(val) {
    if (!val) return [];
    if (Array.isArray(val)) return val;
    if (typeof val === 'object') return Object.values(val);
    return [];
}

/** Normalise stubble/mulch levels from XML or Lua for consistent UI (`isMulched` when level >= 1). */
function normalizeFieldMulch(f) {
    if (!f || typeof f !== 'object') return f;
    const s = Number(f.stubbleShredLevel ?? f.mulchLevel ?? 0);
    const out = { ...f, mulchLevel: s, stubbleShredLevel: s, isMulched: s >= 1 };
    if (String(f.fruitType || '').toUpperCase() === 'GRASS') {
        out.isWithered = false;
    }
    return out;
}

function xmlFieldIndicatesHarvested(xmlField) {
    if (!xmlField) return false;
    if (xmlField.isHarvested === true) return true;
    const gt = String(xmlField.groundType || '').toUpperCase();
    return gt.includes('HARVESTED');
}

/**
 * After harvest, Lua often loses fruitTypeIndex (empty / mulched_stubble) while fields.xml still has BEETROOT etc.
 */
function mergeFieldFruitType(luaField, xmlField) {
    const lua = (luaField.fruitType || '').toUpperCase();
    const xml = (xmlField.fruitType || '').toUpperCase();
    const luaWeak = !luaField.fruitType || lua === 'UNKNOWN' || lua === 'EMPTY' || lua === 'MULCHED_STUBBLE';
    const xmlKnown = xml && xml !== 'UNKNOWN';
    if (luaWeak && xmlKnown) return xmlField.fruitType;
    return luaField.fruitType ?? xmlField.fruitType;
}

function mergeFieldGrowthLabel(luaField, xmlField) {
    if (xmlFieldIndicatesHarvested(xmlField) && luaField.growthLabel === 'mulched_fallow') {
        return 'harvested';
    }
    return luaField.growthLabel ?? xmlField.growthLabel;
}

/** XML collector may provide `allFields` (every farmland incl. unowned) or only player `fields` */
function xmlFieldsBaseForMerge(xmlData) {
    if (!xmlData) return [];
    const all = xmlData.allFields;
    if (Array.isArray(all) && all.length > 0) return all;
    const player = xmlData.fields;
    if (Array.isArray(player) && player.length > 0) return player;
    return [];
}


function mergeData(luaData, xmlData) {
    if (!luaData && !xmlData) return null;
    if (!luaData) return buildFromXmlOnly(xmlData);
    if (!xmlData)  return buildFromLuaOnly(luaData);

    return {
        dataSource   : 'merged',
        xmlAvailable : true,
        luaAvailable : true,
        lastUpdated  : new Date().toISOString(),

        // Identity
        mapTitle     : xmlData.career?.mapTitle     || luaData.serverInfo?.mapName || 'Unknown Map',
        savegameName : xmlData.career?.savegameName || '',
        saveDate     : xmlData.career?.saveDate     || '',
        mapId        : xmlData.career?.mapId        || '',
        settings     : xmlData.career?.settings     || {},
        mods         : xmlData.career?.mods         || [],

        // Farms — XML has players/stats, Lua has live money
        farmInfo     : mergeFarms(toArr(xmlData.farms), toArr(luaData.farmInfo)),

        // Money — Lua is live
        money        : luaData.finance?.money ?? luaData.money ?? xmlData.career?.money ?? 0,
        finance      : luaData.finance || {},

        // Game time — prefer Lua (truly live), fall back to XML environment
        gameTime     : mergeGameTime(luaData.gameTime, xmlData.environment),

        // Weather — merge: XML has accurate forecast, Lua has live temperature
        weather      : mergeWeather(luaData.weather, xmlData.environment),

        // Missions — XML only (Lua doesn't collect these)
        missions     : toArr(xmlData.missions),

        // Animals — Lua only
        animals      : toArr(luaData.animals),

        // Fields — XML provides base (ownership via farmland.xml); prefer allFields so NPC/unowned stay in API
        // Lua provides Precision Farming overlay (N/pH from live density maps)
        fields       : (() => {
                         const xmlBase = xmlFieldsBaseForMerge(xmlData);
                         return mergeFields(
                             xmlBase.length > 0
                               ? xmlBase
                               : fixFieldOwnership(toArr(luaData.fields), xmlData.farmlandOwnership),
                             toArr(luaData.fields)
                         );
                       })(),

        // Vehicles — merge XML (ownership/price) with Lua (live state)
        vehicles     : mergeVehicles(toArr(luaData.vehicles), toArr(xmlData.vehicles)),

        // Economy — XML history + Lua live sell points
        economy      : mergeEconomy(luaData.economy || {}, xmlData.economy || {}),

        // Production — Lua only
        production   : luaData.production || { chains: [], husbandryTotals: {} },

        // Placeables — XML
        placeables   : toArr(xmlData.placeables),

        // Pass through raw data for frontend use
        xmlFarmlands : toArr(xmlData.farmlandsArray),
        xmlEconomy   : xmlData.economy        || {},
    };
}

// ─── farms ────────────────────────────────────────────────────────────────────

function mergeFarms(xmlFarms, luaFarms) {
    const luaMap = new Map(luaFarms.map(f => [f.id, f]));
    const xmlMap = new Map(xmlFarms.map(f => [f.id, f]));
    const allIds = new Set([...xmlMap.keys(), ...luaMap.keys()]);
    return Array.from(allIds).sort().map(id => {
        const xml = xmlMap.get(id) || {};
        const lua = luaMap.get(id) || {};
        return {
            id,
            name       : xml.name       || lua.name       || `Farm ${id}`,
            color      : xml.color      || 1,
            money      : lua.money      ?? xml.money       ?? 0,
            loan       : lua.loan       ?? xml.loan        ?? 0,
            players    : xml.players    || [],
            statistics : xml.statistics || {},
        };
    });
}

// ─── game time ────────────────────────────────────────────────────────────────

function mergeGameTime(luaTime, xmlEnv) {
    if (luaTime && (luaTime.hour !== undefined || luaTime.dayTime)) return luaTime;
    if (!xmlEnv) return {};
    return {
        hour    : xmlEnv.hour,
        minute  : xmlEnv.minute,
        day     : xmlEnv.currentDay,
        dayTime : xmlEnv.dayTime,
    };
}

// ─── weather ──────────────────────────────────────────────────────────────────

function mergeWeather(luaWeather, xmlEnv) {
    const base = luaWeather || {};
    if (!xmlEnv) return base;

    return {
        // Lua provides live temperature; XML provides accurate forecast
        currentTemperature : base.currentTemperature,
        currentWeather     : base.currentWeather     || xmlEnv.currentWeather || 'SUN',
        currentSeason      : xmlEnv.currentSeason    || 'SPRING',
        windSpeed          : base.windSpeed,
        cloudCoverage      : base.cloudCoverage,
        rainLevel          : base.rainLevel,
        snowLevel          : base.snowLevel,
        timeSinceLastRain  : base.timeSinceLastRain,
        // XML forecast is authoritative (exact game engine values)
        forecast           : xmlEnv.forecast?.length > 0 ? xmlEnv.forecast : (base.forecast || []),
        rawForecast        : xmlEnv.rawForecast || [],
    };
}

// ─── field ownership fallback (when XML fields not available) ─────────────────

function fixFieldOwnership(luaFields, farmlandOwnership) {
    if (!farmlandOwnership?.size) return luaFields;
    return luaFields.map(f => {
        if (f.ownerFarmId > 0) return f;
        const resolved = farmlandOwnership.get(f.farmlandId) ||
                         farmlandOwnership.get(parseInt(f.farmlandId));
        return resolved > 0 ? { ...f, ownerFarmId: resolved } : f;
    });
}

// ─── fields ───────────────────────────────────────────────────────────────────

/**
 * Merge XML fields (base data) with Lua fields (Precision Farming overlay).
 *
 * XML fields.xml:        fruitType, growthState, groundType, weedState,
 *                        limeLevel, sprayLevel, plowLevel, ownerFarmId
 * Lua FieldDataCollector: isPrecisionFarming, nitrogenLevel, targetNitrogen,
 *                          phValue, targetPh, phLimeBarMin, phLimeBarMax, isScanned, nitrogenText, limeText,
 *                          posX, posZ, hectares
 *
 * Stubble mulch: Lua `mulchLevel` merged with XML `stubbleShredLevel` when both exist.
 * Lua wins for PF values (only available from runtime density map reads).
 *
 * Suggestions: computed in-game in FieldDataCollector.lua from live state. When both
 * XML and Lua exist for a field, only Lua’s suggestions are exposed (single source).
 */
function mergeFields(xmlFields, luaFields) {
    // Normalise both to arrays — Lua serialises empty tables as {} not []
    const xmlArr = Array.isArray(xmlFields) ? xmlFields
        : (xmlFields && typeof xmlFields === 'object' ? Object.values(xmlFields) : []);
    const luaArr = Array.isArray(luaFields) ? luaFields
        : (luaFields && typeof luaFields === 'object' ? Object.values(luaFields) : []);

    if (luaArr.length === 0) return xmlArr.map(normalizeFieldMulch);
    if (xmlArr.length === 0) return luaArr.map(normalizeFieldMulch);

    // Lua uses internal FieldManager id in `id`; XML fields.xml uses map/farmland field numbers.
    // Key by farmlandId so PF overlay matches the correct physical field (fixes wrong cross-field PF).
    const luaMap = new Map();
    for (const f of luaArr) {
        const key = Number(f.farmlandId ?? f.id);
        if (!Number.isNaN(key)) luaMap.set(key, f);
    }

    const merged = xmlArr.map(xmlField => {
        const xKey = Number(xmlField.farmlandId ?? xmlField.id);
        const luaField = luaMap.get(xKey);
        if (!luaField) return normalizeFieldMulch(xmlField);

        // PF properties only available from Lua density map reads
        const pfOverlay = {
            isPrecisionFarming : luaField.isPrecisionFarming || false,
            nitrogenLevel      : luaField.nitrogenLevel      || 0,
            targetNitrogen     : luaField.targetNitrogen     || 0,
            phValue            : luaField.phValue            || 0,
            targetPh           : luaField.targetPh           || 0,
            phLimeBarMin       : luaField.phLimeBarMin       ?? 0,
            phLimeBarMax       : luaField.phLimeBarMax       ?? 0,
            isScanned          : luaField.isScanned          || false,
            nitrogenText       : luaField.nitrogenText       || xmlField.nitrogenText || '',
            limeText           : luaField.limeText           || xmlField.limeText     || '',
        };

        // Spatial data from Lua (g_fieldManager has actual map coords & hectares)
        const spatialData = {
            posX     : luaField.posX     || luaField.position?.x || xmlField.posX     || 0,
            posZ     : luaField.posZ     || luaField.position?.z || xmlField.posZ     || 0,
            hectares : luaField.hectares || luaField.areaHa      || xmlField.hectares || 0,
        };

        // Single source for suggestions: live Lua (game) when this row is matched.
        // Do not merge XML + Lua lists — different priority scales and stale XML harvest flags.
        const mergedSuggestions = toArr(luaField.suggestions)
            .filter((s) => s && s.action)
            .sort((a, b) => (a.priority || 9) - (b.priority || 9));

        const stubbleMerged = Number(
            luaField.mulchLevel ?? luaField.stubbleShredLevel
            ?? xmlField.stubbleShredLevel ?? xmlField.mulchLevel ?? 0
        );

        const luaMaxGs = Number(luaField.maxGrowthState);
        const luaGs    = Number(luaField.growthState);
        const luaPct   = luaField.growthStatePercentage;
        const mergedFruitType = mergeFieldFruitType(luaField, xmlField);

        return {
            ...xmlField,    // XML base: soil state, ownership, crop, growthState
            ...spatialData, // Lua: map position and area
            ...pfOverlay,   // Lua: Precision Farming nitrogen/pH
            // Lua is authoritative: XML uses coarse heuristics (e.g. plowLevel < 1 on growing crops).
            needsWork   : luaField.needsWork ?? xmlField.needsWork ?? false,
            needsRolling: luaField.needsRolling === true,
            rollerLevel : luaField.rollerLevel ?? xmlField.rollerLevel ?? 0,
            suggestions : mergedSuggestions,
            mulchLevel       : stubbleMerged,
            stubbleShredLevel: stubbleMerged,
            isMulched        : stubbleMerged >= 1,
            isHarvested      : !!(luaField.isHarvested || xmlField.isHarvested),
            growthLabel      : mergeFieldGrowthLabel(luaField, xmlField),
            // Grass is perennial — never keep arable "withered" from XML when merged with Lua
            isWithered       : String(mergedFruitType || '').toUpperCase() === 'GRASS'
                ? false
                : !!(luaField.isWithered ?? xmlField.isWithered),
            // Lua live crop + stage counts (XML uses flat maxGrowthState=8 for all crops)
            fruitType             : mergedFruitType,
            fruitTypeIndex        : (Number(luaField.fruitTypeIndex) > 0)
                ? luaField.fruitTypeIndex
                : xmlField.fruitTypeIndex,
            growthState           : Number.isFinite(luaGs) ? luaGs : xmlField.growthState,
            maxGrowthState        : (Number.isFinite(luaMaxGs) && luaMaxGs > 0) ? luaMaxGs : xmlField.maxGrowthState,
            growthStatePercentage : (luaPct != null && luaPct !== '') ? luaPct : xmlField.growthStatePercentage,
        };
    });

    return merged;
}

// ─── vehicles ─────────────────────────────────────────────────────────────────

function mergeVehicles(luaVehicles, xmlVehicles) {
    // Build position-indexed lookup for XML vehicles
    const xmlByPos = xmlVehicles.filter(v => v.position);

    const merged = luaVehicles.map(luaV => {
        let xmlV = null;
        if (luaV.position) {
            let best = Infinity;
            for (const xv of xmlByPos) {
                const d = Math.hypot(luaV.position.x - xv.position.x,
                                     luaV.position.z - xv.position.z);
                if (d < 5 && d < best) { best = d; xmlV = xv; }
            }
        }
        return {
            ...luaV,
            ownerFarmId   : luaV.ownerFarmId || xmlV?.farmId || 0,
            farmId        : luaV.ownerFarmId || xmlV?.farmId || 0,
            price         : luaV.price  || xmlV?.price  || 0,
            age           : luaV.age    || xmlV?.age    || 0,
            uniqueId      : xmlV?.uniqueId || luaV.id,
            filename      : xmlV?.filename || '',
            xmlFillLevels : xmlV?.fillLevels || {},
            source        : xmlV ? 'merged' : 'lua_only',
        };
    });

    // Add XML-only vehicles (not in Lua — off-map / stored)
    const luaPos = luaVehicles.filter(v => v.position).map(v => v.position);
    for (const xv of xmlVehicles) {
        if (!xv.position) continue;
        const present = luaPos.some(lp =>
            Math.hypot(lp.x - xv.position.x, lp.z - xv.position.z) < 5);
        if (!present) {
            merged.push({
                id: xv.uniqueId, uniqueId: xv.uniqueId,
                name: xv.name, filename: xv.filename,
                farmId: xv.farmId, ownerFarmId: xv.farmId,
                price: xv.price, age: xv.age,
                operatingTime: xv.operatingTime,
                damage: xv.damage, fillLevels: xv.fillLevels,
                xmlFillLevels: xv.fillLevels,
                position: xv.position,
                isMotorized: false, engineOn: false, speed: 0,
                source: 'xml_only',
            });
        }
    }

    return merged;
}

// ─── economy ──────────────────────────────────────────────────────────────────

function mergeEconomy(luaEconomy, xmlEconomy) {
    const result = { ...luaEconomy, xmlPriceHistory: xmlEconomy };

    // Enrich Lua crop entries with XML price history
    if (luaEconomy.marketPrices?.crops && xmlEconomy) {
        for (const [crop, data] of Object.entries(luaEconomy.marketPrices.crops)) {
            const hist = xmlEconomy[crop] || xmlEconomy[crop.toUpperCase()];
            if (hist) {
                data.priceHistory     = hist.history;
                data.avgXmlPrice      = hist.avgPrice;
                data.totalHarvested   = hist.totalAmount;
            }
        }
    }
    return result;
}

// ─── single-source fallbacks ──────────────────────────────────────────────────

function buildFromLuaOnly(lua) {
    return {
        dataSource: 'lua_only', xmlAvailable: false, luaAvailable: true,
        lastUpdated: new Date().toISOString(),
        mapTitle: lua.serverInfo?.mapName || 'Unknown Map',
        savegameName: '', settings: {}, mods: [],
        gameTime: lua.gameTime || {},
        farmInfo: lua.farmInfo || [],
        money: lua.finance?.money ?? lua.money ?? 0,
        finance: lua.finance || {},
        weather: lua.weather || {},
        missions: [],
        animals: lua.animals || [],
        fields: toArr(lua.fields).map(normalizeFieldMulch),
        vehicles: lua.vehicles || [],
        economy: lua.economy   || {},
        production: lua.production || {},
        placeables: [],
    };
}

function buildFromXmlOnly(xml) {
    return {
        dataSource: 'xml_only', xmlAvailable: true, luaAvailable: false,
        lastUpdated: new Date().toISOString(),
        mapTitle: xml.career?.mapTitle || 'Unknown Map',
        savegameName: xml.career?.savegameName || '',
        saveDate: xml.career?.saveDate || '',
        settings: xml.career?.settings || {},
        mods: xml.career?.mods || [],
        gameTime: xml.environment ? {
            hour: xml.environment.hour, minute: xml.environment.minute,
            day: xml.environment.currentDay, dayTime: xml.environment.dayTime,
        } : {},
        farmInfo: xml.farms || [],
        money: xml.career?.money || 0,
        finance: { money: xml.career?.money || 0 },
        weather: xml.environment ? {
            currentWeather: xml.environment.currentWeather,
            currentSeason: xml.environment.currentSeason,
            forecast: xml.environment.forecast || [],
        } : {},
        missions: xml.missions || [],
        animals: [],
        fields: toArr((xml.allFields && xml.allFields.length > 0) ? xml.allFields : (xml.fields || [])).map(normalizeFieldMulch),
        vehicles: xml.vehicles || [],
        economy: { xmlPriceHistory: xml.economy || {} },
        production: {},
        placeables: xml.placeables || [],
        xmlFarmlands: xml.farmlandsArray || [],
        xmlEconomy: xml.economy || {},
    };
}

module.exports = { mergeData };