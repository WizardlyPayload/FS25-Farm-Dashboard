// FS25 FarmDashboard | xmlCollector.js | v1.0.0

/**
 * xmlCollector.js  —  FS25 Savegame XML Reader
 *
 * Parses all useful XML files from the savegame folder and returns
 * structured data ready for dataMerger.js.
 *
 * Files handled:
 *   careerSavegame.xml  — settings, map name, mod list
 *   farms.xml           — farm names, money, loan, players, statistics
 *   farmland.xml        — farmlandId → farmId ownership map  (KEY: fixes fields)
 *   fields.xml          — complete field state: crop, growthState, weed, soil
 *   environment.xml     — current day/time + full weather forecast
 *   missions.xml        — active missions with rewards and field IDs
 *   vehicles.xml        — all owned vehicles with fill levels / damage
 *   economy.xml         — 12-period crop price history
 *   placeables.xml      — all placed buildings / silos
 */

const fs   = require('fs');
const path = require('path');
const os   = require('os');

// ─── tiny XML helpers (no external parser needed) ────────────────────────────

function readXml(filePath) {
    try {
        if (!fs.existsSync(filePath)) return null;
        return fs.readFileSync(filePath, 'utf8');
    } catch (e) {
        console.warn(`[XML] Cannot read ${path.basename(filePath)}: ${e.message}`);
        return null;
    }
}

function attr(str, name, fallback = null) {
    const m = str.match(new RegExp(`\\b${name}="([^"]*)"`));
    return m ? m[1] : fallback;
}

function textContent(xml, tag) {
    const m = xml.match(new RegExp(`<${tag}[^>]*>([^<]*)<\/${tag}>`));
    return m ? m[1].trim() : null;
}

// ─── savegame path resolution ─────────────────────────────────────────────────

/** Same bundle main.js downloads over FTP (GPortal / dedicated: profile/savegameN/…). */
const SAVEGAME_XML_FILES = [
    'careerSavegame.xml',
    'farmland.xml',
    'fields.xml',
    'farms.xml',
    'environment.xml',
    'missions.xml',
    'vehicles.xml',
    'economy.xml',
    'placeables.xml',
    'precisionFarming.xml',
];

function getSavegamePath(srv, saveSlot) {
    const slot = saveSlot || srv.localSubFolder || 'savegame1';

    // FTP: files are downloaded to a local cache by main.js (see downloadFtpSavegameXml)
    if (srv.mode === 'ftp') {
        try {
            const { app } = require('electron');
            return path.join(app.getPath('userData'), 'ftpXmlCache', srv.id, slot);
        } catch (e) {
            console.warn('[XML] FTP savegame cache path unavailable:', e.message);
            return null;
        }
    }

    // The mod writes data.json to:
    //   .../FarmingSimulator2025/modSettings/FS25_FarmDashboard/<saveSlot>/data.json
    // The savegame XML files are at:
    //   .../FarmingSimulator2025/<saveSlot>/careerSavegame.xml

    const slotLocal = srv.localSubFolder || saveSlot || 'savegame1';

    // Try to find the FS25 root from the localPath
    if (srv.localPath) {
        // localPath is usually the modSettings/FS25_FarmDashboard folder
        // Go up to find FarmingSimulator2025 root
        let check = srv.localPath;
        for (let i = 0; i < 6; i++) {
            const candidate = path.join(check, slotLocal);
            if (fs.existsSync(path.join(candidate, 'careerSavegame.xml'))) return candidate;
            check = path.dirname(check);
        }
    }

    // Standard default path
    const fs25Root = path.join(os.homedir(), 'Documents', 'My Games', 'FarmingSimulator2025');
    const direct   = path.join(fs25Root, slotLocal);
    if (fs.existsSync(path.join(direct, 'careerSavegame.xml'))) return direct;

    // Try without slot (maybe localPath IS the savegame folder)
    if (srv.localPath && fs.existsSync(path.join(srv.localPath, 'careerSavegame.xml'))) {
        return srv.localPath;
    }

    console.warn(`[XML] Could not locate savegame folder for slot "${slotLocal}"`);
    return direct; // best guess — caller checks if files exist
}

// ─── parsers ──────────────────────────────────────────────────────────────────

function parseCareerSavegame(xml) {
    if (!xml) return {};
    const mods = [];
    const modRe = /<mod\s+modName="([^"]+)"\s+title="([^"]+)"/g;
    let mm;
    while ((mm = modRe.exec(xml)) !== null) mods.push({ modName: mm[1], title: mm[2] });

    return {
        savegameName : textContent(xml, 'savegameName'),
        mapId        : textContent(xml, 'mapId'),
        mapTitle     : textContent(xml, 'mapTitle'),
        saveDate     : textContent(xml, 'saveDateFormatted') || textContent(xml, 'saveDate'),
        creationDate : textContent(xml, 'creationDate'),
        money        : parseFloat(textContent(xml, 'money') || '0'),
        playTime     : parseFloat(textContent(xml, 'playTime') || '0'),
        economicDifficulty   : textContent(xml, 'economicDifficulty'),
        growthMode   : textContent(xml, 'growthMode'),
        timeScale    : parseFloat(textContent(xml, 'timeScale') || '1'),
        plannedDaysPerPeriod : parseInt(textContent(xml, 'plannedDaysPerPeriod') || '2'),
        settings: {
            weedsEnabled      : textContent(xml, 'weedsEnabled')          === 'true',
            limeRequired      : textContent(xml, 'limeRequired')          === 'true',
            plowingRequired   : textContent(xml, 'plowingRequiredEnabled') === 'true',
            stonesEnabled     : textContent(xml, 'stonesEnabled')         === 'true',
            fruitDestruction  : textContent(xml, 'fruitDestruction')      === 'true',
            snowEnabled       : textContent(xml, 'isSnowEnabled')         === 'true',
            trafficEnabled    : textContent(xml, 'trafficEnabled')        === 'true',
            fuelUsage         : textContent(xml, 'fuelUsage'),
            helperBuySeeds    : textContent(xml, 'helperBuySeeds')        === 'true',
            helperBuyFuel     : textContent(xml, 'helperBuyFuel')         === 'true',
            helperBuyFertilizer : textContent(xml, 'helperBuyFertilizer') === 'true',
        },
        mods,
    };
}

/**
 * farmland.xml  →  Map<farmlandId, farmId>
 * Also returns Set<farmlandId> owned by player farms (farmId > 0)
 */
function parseFarmlandXml(xml) {
    if (!xml) return { ownership: new Map(), playerFarmlandIds: new Set() };
    const ownership        = new Map();
    const playerFarmlandIds = new Set();
    const re = /<farmland\s([^/>\r\n]*)\/?>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const id     = parseInt(attr(m[1], 'id') || '0');
        const farmId = parseInt(attr(m[1], 'farmId') || '0');
        if (id > 0) {
            ownership.set(id, farmId);
            if (farmId > 0) playerFarmlandIds.add(id);
        }
    }
    return { ownership, playerFarmlandIds };
}

/**
 * fields.xml  →  array of field objects
 * Fields use the same IDs as farmlands — join via farmland.xml to get ownerFarmId.
 *
 * groundType values: PLOWED, CULTIVATED, SOWN, DIRECT_SOWN, GRASS,
 *                    HARVEST_READY, HARVEST_READY_OTHER, HARVESTED
 */
function parseFieldsXml(xml, farmlandOwnership, scannedFarmlands, farmlandStats) {
    if (!xml) return [];
    const fields = [];
    const re = /<field\s([^/>\r\n]*)\/?>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const a = m[1];
        const id          = parseInt(attr(a, 'id') || '0');
        const fruitType   = attr(a, 'fruitType')   || 'UNKNOWN';
        const growthState = parseInt(attr(a, 'growthState') || '0');
        const groundType  = attr(a, 'groundType')  || 'UNKNOWN';
        const weedState   = parseInt(attr(a, 'weedState')   || '0');
        const limeLevel   = parseInt(attr(a, 'limeLevel')   || '0');
        const sprayLevel  = parseInt(attr(a, 'sprayLevel')  || '0');
        const sprayType   = attr(a, 'sprayType')   || 'NONE';
        const plowLevel   = parseInt(attr(a, 'plowLevel')   || '0');
        const stubble     = parseInt(attr(a, 'stubbleShredLevel') || '0');
        const lastGrowth  = parseInt(attr(a, 'lastGrowthState')   || '0');
        const plannedFruit = attr(a, 'plannedFruit') || 'FALLOW';
        const stoneLevel  = parseInt(attr(a, 'stoneLevel')  || '0');

        // Resolve ownership via farmland.xml join
        const ownerFarmId = farmlandOwnership ? (farmlandOwnership.get(id) || 0) : 0;

        // Check if this farmland has been soil-sampled (Precision Farming)
        const isScanned   = scannedFarmlands ? scannedFarmlands.has(id) : false;
        const pfStats     = farmlandStats ? (farmlandStats[id] || null) : null;

        // Derive status flags
        const isHarvestReady = groundType.includes('HARVEST_READY');
        const isHarvested    = groundType.includes('HARVESTED');
        // Grass does not wither like arable crops; ignore WITHERED ground / stage heuristics for GRASS
        const isWithered     = fruitType !== 'GRASS' && growthState > 0 &&
            (groundType === 'WITHERED' || (fruitType !== 'UNKNOWN' && growthState > 12));
        const isEmpty        = fruitType === 'UNKNOWN' || growthState === 0;
        const needsWork      = weedState > 2 || limeLevel < 1 || sprayLevel < 1 || plowLevel < 1;

        // Approximate growth % (grass uses 4 stages in FS25; other crops often ~8)
        const maxGrowthEst   = fruitType === 'GRASS' ? 4 : 8;
        const growthPct      = isEmpty ? 0 : Math.min(100, Math.round((growthState / maxGrowthEst) * 100));

        // Human-readable suggestions (grass: plain wording, not "Harvest GRASS")
        const suggestions = [];
        if (isHarvestReady) {
            const ftU = String(fruitType || '').toUpperCase();
            const harvestAction = ftU === 'GRASS' ? 'Harvest grass' : `Harvest ${fruitType}`;
            suggestions.push({ priority: 1, action: harvestAction, type: 'harvest' });
        }
        else if (isEmpty && plowLevel > 0) suggestions.push({ priority: 2, action: 'Cultivate or direct drilling', type: 'planting' });
        else if (!isEmpty && weedState > 2) suggestions.push({ priority: 3, action: 'Spray weeds',       type: 'maintenance' });
        if (limeLevel < 1)           suggestions.push({ priority: 4, action: 'Apply lime',               type: 'maintenance' });
        if (sprayLevel < 1 && !isEmpty) suggestions.push({ priority: 4, action: 'Fertilize',             type: 'maintenance' });
        if (plowLevel < 1 && isEmpty)   suggestions.push({ priority: 5, action: 'Plow field',            type: 'preparation' });
        suggestions.sort((a, b) => a.priority - b.priority);

        fields.push({
            id, ownerFarmId, farmlandId: id,
            fruitType, plannedFruit,
            growthState, lastGrowthState: lastGrowth,
            maxGrowthState: maxGrowthEst,
            growthStatePercentage: growthPct,
            groundType, weedState,
            limeLevel, sprayLevel, sprayType,
            plowLevel, stubbleShredLevel: stubble,
            stoneLevel,
            harvestReady: isHarvestReady,
            isHarvested,
            isWithered, needsWork,
            suggestions,
            // Precision farming placeholders (filled if PF data available)
            isPrecisionFarming: false,
            nitrogenLevel: 0, targetNitrogen: 0,
            phValue: 0, targetPh: 0, isScanned: false,
            nitrogenText: `${sprayLevel}/2`, limeText: limeLevel >= 1 ? 'OK' : 'Needed',
            // PF soil scan status from precisionFarming.xml
            isScanned, pfStats,
        });
    }
    return fields;
}

function parseFarmsXml(xml) {
    if (!xml) return [];
    const farms = [];
    const farmRe = /<farm\s([^>]*)>([\s\S]*?)<\/farm>/g;
    let m;
    while ((m = farmRe.exec(xml)) !== null) {
        const attrs  = m[1];
        const inner  = m[2];
        const farmId = parseInt(attr(attrs, 'farmId') || '0');
        if (farmId === 0) continue;

        // Players
        const players = [];
        const plRe = /<player\s([^/>\r\n]*)\/?>/g;
        let pm;
        while ((pm = plRe.exec(inner)) !== null) {
            players.push({
                userId         : attr(pm[1], 'uniqueUserId'),
                nickname       : attr(pm[1], 'lastNickname') || 'Unknown',
                lastConnected  : attr(pm[1], 'timeLastConnected'),
                isFarmManager  : attr(pm[1], 'farmManager') === 'true',
            });
        }

        // Statistics
        const stats = {};
        const statFields = [
            'traveledDistance','fuelUsage','seedUsage','sprayUsage',
            'workedHectares','cultivatedHectares','sownHectares','sprayedHectares',
            'threshedHectares','plowedHectares','workedTime','baleCount',
            'revenue','expenses','playTime','repairVehicleCount',
            'wrappedBales','tractorDistance','carDistance','truckDistance',
        ];
        statFields.forEach(f => {
            const v = textContent(inner, f);
            if (v !== null) stats[f] = parseFloat(v);
        });

        farms.push({
            id    : farmId,
            name  : attr(attrs, 'name') || `Farm ${farmId}`,
            color : parseInt(attr(attrs, 'color') || '1'),
            money : parseFloat(attr(attrs, 'money') || '0'),
            loan  : parseFloat(attr(attrs, 'loan')  || '0'),
            players,
            statistics: stats,
        });
    }
    return farms;
}

/**
 * environment.xml  →  current time + full forecast
 */
function parseEnvironmentXml(xml) {
    if (!xml) return {};
    const dayTime    = parseFloat(textContent(xml, 'dayTime') || '0');
    const currentDay = parseInt(textContent(xml, 'currentDay') || '1');

    // dayTime is in milliseconds within the day
    const dayMs   = dayTime;
    const hour    = Math.floor(dayMs / 3600000);
    const minute  = Math.floor((dayMs % 3600000) / 60000);

    // Parse forecast instances
    const forecast = [];
    const re = /<instance\s([^/>\r\n]*)\/?>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const a = m[1];
        forecast.push({
            typeName      : attr(a, 'typeName')     || 'SUN',
            season        : attr(a, 'season')        || 'SPRING',
            startDay      : parseInt(attr(a, 'startDay')     || '0'),
            startDayTime  : parseInt(attr(a, 'startDayTime') || '0'),
            duration      : parseInt(attr(a, 'duration')     || '0'),
        });
    }

    // Find current weather (instance that covers right now)
    const nowMs = currentDay * 86400000 + dayMs;
    const currentForecast = forecast.find(f => {
        const start = f.startDay * 86400000 + f.startDayTime;
        const end   = start + f.duration;
        return nowMs >= start && nowMs < end;
    }) || forecast[0];

    // Build 3-day forecast summary grouped by day
    const byDay = {};
    forecast.forEach(f => {
        if (f.startDay > currentDay && f.startDay <= currentDay + 3) {
            if (!byDay[f.startDay]) byDay[f.startDay] = [];
            byDay[f.startDay].push(f.typeName);
        }
    });
    const forecastDays = Object.entries(byDay).map(([day, types]) => ({
        day         : parseInt(day),
        weatherType : types[0],   // dominant type for the day
        allTypes    : types,
        minTemperature: null,     // not in XML — Lua provides this
        maxTemperature: null,
        precipitationChance: types.includes('RAIN') || types.includes('SNOW') ? 80 : 20,
    }));

    return {
        dayTime, currentDay, hour, minute,
        currentWeather : currentForecast?.typeName  || 'SUN',
        currentSeason  : currentForecast?.season    || 'SPRING',
        forecast       : forecastDays,
        rawForecast    : forecast,
    };
}

/**
 * missions.xml  →  array of active missions
 */
function parseMissionsXml(xml) {
    if (!xml) return [];
    const missions = [];
    // Match any *Mission tag
    const re = /<(\w+Mission)\s([^>]*)>([\s\S]*?)<\/\1>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const type  = m[1];
        const attrs = m[2];
        const inner = m[3];

        const uniqueId = attr(attrs, 'uniqueId');
        const status   = attr(attrs, 'status')      || 'CREATED';
        const reward   = parseInt(textContent(inner, 'reward') || attr(inner, 'reward') || '0');
        const endDay   = parseInt(attr(inner.match(/<endDate([^/]*)\/>/)?.[1] || '', 'endDay') || '0');

        // Field IDs referenced
        const fieldIds = [];
        const fRe = /<field\s+id="(\d+)"/g;
        let fm;
        while ((fm = fRe.exec(inner)) !== null) fieldIds.push(parseInt(fm[1]));

        missions.push({
            uniqueId, type, status, reward, endDay, fieldIds,
            completion : parseFloat(attr(inner, 'completion') || '0'),
        });
    }
    return missions;
}

function parseVehiclesXml(xml) {
    if (!xml) return [];
    const vehicles = [];
    const re = /<vehicle\s([^>]*)>([\s\S]*?)<\/vehicle>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const outerAttrs = m[1];
        const inner      = m[2];
        const farmId     = parseInt(attr(outerAttrs, 'farmId') || '0');
        if (farmId === 0) continue;

        const fillLevels = {};
        const fRe = /<unit[^>]+fillType="([^"]+)"[^>]+fillLevel="([^"]+)"/g;
        let fm;
        while ((fm = fRe.exec(inner)) !== null) fillLevels[fm[1]] = parseFloat(fm[2]);

        const posM    = inner.match(/position="([^"]+)"/);
        const damM    = inner.match(/damage="([^"]+)"/);
        const posStr  = posM ? posM[1].split(' ') : ['0','0','0'];

        const filename  = attr(outerAttrs, 'filename') || '';
        const nameParts = filename.replace(/\\/g, '/').split('/');
        const rawName   = nameParts[nameParts.length - 1].replace('.xml', '');

        vehicles.push({
            uniqueId     : attr(outerAttrs, 'uniqueId'),
            filename, name: rawName,
            farmId, ownerFarmId: farmId,
            age          : parseFloat(attr(outerAttrs, 'age')           || '0'),
            price        : parseFloat(attr(outerAttrs, 'price')         || '0'),
            operatingTime: parseFloat(attr(outerAttrs, 'operatingTime') || '0'),
            propertyState: attr(outerAttrs, 'propertyState') || 'OWNED',
            damage       : damM ? parseFloat(damM[1]) : 0,
            fillLevels,
            position     : { x: parseFloat(posStr[0]), y: parseFloat(posStr[1]), z: parseFloat(posStr[2]) },
            source       : 'xml',
        });
    }
    return vehicles;
}

function parseEconomyXml(xml) {
    if (!xml) return {};
    const prices = {};
    const re = /<fillType fillType="([^"]+)"([^>]*)>([\s\S]*?)<\/fillType>/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const cropName    = m[1];
        const totalAmount = parseFloat(attr(m[2] + ' ', 'totalAmount') || '0');
        const inner       = m[3];
        const history     = {};
        const pRe = /<period period="([^"]+)">(\d+)<\/period>/g;
        let pm;
        while ((pm = pRe.exec(inner)) !== null) history[pm[1]] = parseInt(pm[2]);
        if (Object.keys(history).length === 0) continue;
        const vals = Object.values(history);
        prices[cropName] = {
            history,
            avgPrice    : Math.round(vals.reduce((a, b) => a + b, 0) / vals.length),
            minPrice    : Math.min(...vals),
            maxPrice    : Math.max(...vals),
            totalAmount,
        };
    }
    return prices;
}

function parsePlaceablesXml(xml) {
    if (!xml) return [];
    const placeables = [];
    // Match both self-closing and block placeables
    const re = /<placeable\s([^>]*)(?:\/>|>[\s\S]*?<\/placeable>)/g;
    let m;
    while ((m = re.exec(xml)) !== null) {
        const attrs  = m[1];
        const farmId = parseInt(attr(attrs, 'farmId') || '0');
        if (farmId === 0) continue;
        placeables.push({
            uniqueId : attr(attrs, 'uniqueId'),
            farmId,
            age      : parseFloat(attr(attrs, 'age')   || '0'),
            price    : parseFloat(attr(attrs, 'price')  || '0'),
        });
    }
    return placeables;
}


/**
 * precisionFarming.xml  →  per-farmland statistics and tramline data
 * Also tells us which farmlands have been soil-sampled (numSoilSamples > 0)
 */
function parsePrecisionFarmingXml(xml) {
    if (!xml) return { scannedFarmlands: new Set(), farmlandStats: {} };

    const scannedFarmlands = new Set();
    const farmlandStats    = {};

    // Tramline data
    const tramlines = {};
    const tlRe = /<farmland farmlandId="(\d+)" width="([^"]+)" workDirection="([^"]+)" spacing="([^"]+)"/g;
    let tm;
    while ((tm = tlRe.exec(xml)) !== null) {
        tramlines[parseInt(tm[1])] = {
            width        : parseFloat(tm[2]),
            workDirection: parseFloat(tm[3]),
            spacing      : parseFloat(tm[4]),
        };
    }

    // Per-farmland statistics — check if soil samples have been taken
    const statRe = /<farmlandStatistic farmlandId="(\d+)">[\s\S]*?<\/farmlandStatistic>/g;
    let sm;
    while ((sm = statRe.exec(xml)) !== null) {
        const farmlandId = parseInt(sm[1]);
        const inner      = sm[0];

        // totalCounter has cumulative stats
        const totalM = inner.match(/<totalCounter([^/]*)\/>/);
        if (totalM) {
            const tc = totalM[1];
            const numSamples = parseInt(attr(tc, 'numSoilSamples') || '0');
            const yield_     = parseFloat(attr(tc, 'yield')         || '0');
            const yieldWeight= parseFloat(attr(tc, 'yieldWeight')   || '0');
            const bestPrice  = parseFloat(attr(tc, 'yieldBestPrice')|| '0');
            const usedLime   = parseFloat(attr(tc, 'usedLime')      || '0');
            const usedFert   = parseFloat(attr(tc, 'usedMineralFertilizer') || '0') +
                               parseFloat(attr(tc, 'usedLiquidFertilizer')  || '0');
            const usedManure = parseFloat(attr(tc, 'usedManure')    || '0') +
                               parseFloat(attr(tc, 'usedLiquidManure') || '0');
            const usedFuel   = parseFloat(attr(tc, 'usedFuel')      || '0');
            const subsidies  = parseFloat(attr(tc, 'subsidies')     || '0');
            const vehicleCosts = parseFloat(attr(tc, 'vehicleCosts')|| '0');

            if (numSamples > 0) scannedFarmlands.add(farmlandId);

            farmlandStats[farmlandId] = {
                numSoilSamples: numSamples,
                yield: yield_, yieldWeight, yieldBestPrice: bestPrice,
                usedLime, usedFertilizer: usedFert,
                usedManure, usedFuel, subsidies, vehicleCosts,
                tramline: tramlines[farmlandId] || null,
            };
        }
    }

    return { scannedFarmlands, farmlandStats, tramlines };
}

// ─── main export ─────────────────────────────────────────────────────────────

async function collectXmlData(srv, saveSlot) {
    const savegameDir = getSavegamePath(srv, saveSlot);
    if (!savegameDir) return null;

    const file = f => path.join(savegameDir, f);
    const has  = f => fs.existsSync(file(f));

    if (!has('careerSavegame.xml') && !has('fields.xml')) {
        console.log(`[XML] No savegame files found at: ${savegameDir}`);
        return null;
    }
    console.log(`[XML] Reading savegame from: ${savegameDir}`);

    // Parse farmland first — needed for field ownership join
    const { ownership: farmlandOwnership, playerFarmlandIds } =
        parseFarmlandXml(readXml(file('farmland.xml')));

    const career     = parseCareerSavegame(readXml(file('careerSavegame.xml')));
    const pfData     = parsePrecisionFarmingXml(readXml(file('precisionFarming.xml')));
    const farms      = parseFarmsXml(readXml(file('farms.xml')));
    const fields     = parseFieldsXml(readXml(file('fields.xml')), farmlandOwnership, pfData.scannedFarmlands, pfData.farmlandStats);
    const environment= parseEnvironmentXml(readXml(file('environment.xml')));
    const missions   = parseMissionsXml(readXml(file('missions.xml')));
    const vehicles   = parseVehiclesXml(readXml(file('vehicles.xml')));
    const economy    = parseEconomyXml(readXml(file('economy.xml')));
    const placeables = parsePlaceablesXml(readXml(file('placeables.xml')));

    // Filter fields to only player-owned (farmId > 0)
    const playerFields = fields.filter(f => f.ownerFarmId > 0);

    console.log(`[XML] Parsed: farms=${farms.length} fields=${playerFields.length}/${fields.length} vehicles=${vehicles.length} missions=${missions.length} crops=${Object.keys(economy).length}`);

    return {
        career, farms,
        farmlandsArray: Array.from(farmlandOwnership.entries())
            .map(([id, farmId]) => ({ farmlandId: id, farmId })),
        farmlandOwnership,  // Map object for merger to use
        fields: playerFields,
        allFields: fields,  // including unowned, for reference
        environment,
        missions,
        vehicles,
        economy,
        placeables,
        pfData,
        savegameDir,
        collectedAt: new Date().toISOString(),
    };
}

module.exports = { collectXmlData, getSavegamePath, SAVEGAME_XML_FILES };