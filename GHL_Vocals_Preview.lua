version_num="1.1"

-- Rastrea el proyecto actual
local currentProject = reaper.EnumProjects(-1)

-- Detecta cambios en la pista de voces
local vocalsHash = ""

-- Nota MIDI para Hero Power
HP=116

-- Estado de la reproducción
curBeat=0

-- RGBA -> 1.0
local function rgb2num(r, g, b)
    g = g * 256
    b = b * 256 * 256
    return r + g + b
end

gfx.clear = rgb2num(35, 38, 52) -- Background color
gfx.init("GHL Vocals Preview", 1000, 300, 0, 480, 390) -- Alto, Ancho, Eje X, Eje Y

-- Variables para el visualizador de letras
local vocalsTrack = nil
local phrases = {}
local currentPhrase = 1
local phraseMarkerNote = 105  -- Nota MIDI para el marcador de frases
local showLyrics = true       -- Controla si se muestra el visualizador de letras
local showNotesHUD = true     -- Controla si se muestra el visualizador de líneas de notas

-- Colores para las letras
local textColorInactive = {r = 0.15, g = 0.9, b = 0.0, a = 1.0}  -- Verde
local textColorActive = {r = 0.0, g = 1.0, b = 1.0, a = 1.0}    -- Azul
local textColorSung = {r = 0.1176471, g = 0.5647059, b = 1.0, a = 1.0}  -- Azul claro para letras ya cantadas
local bgColorLyrics = {r = 0.15, g = 0.15, b = 0.25, a = 0.8}   -- Fondo para letras

-- Color para la próxima frase (notas con tono)
local textColorNextPhrase = {r = 0.0, g = 1.0, b = 0.5, a = 1.0}  -- Verde más claro para próxima frase

-- Color para letras sin tono (marcadas con #)
local textColorToneless = {r = 0.55, g = 0.55, b = 0.55, a = 1.0}  -- Gris para letras sin tono
local textColorTonelessActive = {r = 1.0, g = 1.0, b = 1.0, a = 1.0}  -- Blanco puro para letras sin tono activas
local textColorTonelessSung = {r = 0.75, g = 0.75, b = 0.75, a = 1.0}  -- Blanco puro para letras sin tono ya cantadas

-- Colores en la sección de colores al inicio del script
local textColorHeroPower = {r = 1.0, g = 1.0, b = 0.15, a = 1.0}  -- Amarillo para letras con Hero Power
local textColorHeroPowerActive = {r = 1.0, g = 0.5, b = 0.3, a = 1.0}  -- Amarillo brillante para letras Hero Power activas
local textColorHeroPowerSung = {r = 0.9764706, g = 0.8999952, b = 0.5372549, a = 1.0}  -- Amarillo más oscuro para letras Hero Power ya cantadas

-- Variables configurables para ajustar la posición y tamaño del visualizador de letras
local lyricsConfig = {
    height = 110,           -- Altura total del visualizador
    bottomMargin = 30,      -- Margen inferior (negativo = se superpone con el borde)
    phraseHeight = 35,      -- Altura de cada frase (reducida ligeramente)
    phraseSpacing = 1,      -- Espacio entre frases
    bgOpacity = 0.8,        -- Opacidad del fondo (0.0 - 1.0)
    fontSize = {            -- Tamaños de fuente
        current = 24,       -- Tamaño para frase actual
        next = 22           -- Tamaño para próxima frase
    }
}

function findTrack(trackName)
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        local _, currentTrackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if currentTrackName == trackName then
            return track
        end
    end
    return nil
end

-- Función para reiniciar el estado cuando cambia el proyecto
function resetState()
    vocalsTrack = nil
    vocalsHash = ""
    phrases = {}
    currentPhrase = 1
end

-- Función de seguridad para comprobar si una pista sigue siendo válida
function isTrackValid(track)
    if track == nil then return false end
    
    local success, _ = pcall(function()
        reaper.GetTrackGUID(track)
    end)
    
    return success
end

-- Estructura para una frase de letras
function createPhrase(startTime, endTime)
    return {
        startTime = startTime,
        endTime = endTime,
        lyrics = {},
        currentLyric = 1
    }
end

-- Función para comprobar si hay algún proyecto abierto
function isProjectOpen()
    local proj = reaper.EnumProjects(-1)
    return proj ~= nil
end

-- Función para verificar si la pista PART VOCALS sigue siendo válida
function checkVocalsTrack()
    -- Si la pista PART VOCALS no está definida o no es válida, se resetea
    if not vocalsTrack or not isTrackValid(vocalsTrack) then
        vocalsTrack = nil
        return false
    end
    return true
end

-- Función completa createLyric con soporte para Hero Power
function createLyric(text, startTime, endTime, pitch, hasHeroPower)
    -- Procesar el texto
    local processedText = text
    local originalText = text  -- Guardar el texto original para referencia
    
    -- Detectar si es una letra sin tono (#)
    local hasTonelessMarker = processedText:match("#") ~= nil or processedText:match("%^") ~= nil
    
    -- Análisis de conectores en el texto ORIGINAL
    -- Buscar todos los posibles patrones de conector al final
    local connectsWithNext = false
    if originalText:match("%-$") or originalText:match("%+$") or originalText:match("=$") or
       originalText:match("%-#$") or originalText:match("%+#$") or originalText:match("=#$") or
       originalText:match("%-%^$") or originalText:match("=^$") then
        connectsWithNext = true
    end
    
    -- Buscar todos los posibles patrones de conector al principio
    local connectsWithPrevious = false
    if originalText:match("^%-") or originalText:match("^%+") or originalText:match("^=") or
       originalText:match("^%-#") or originalText:match("^%+#") or originalText:match("^=#") then
        connectsWithPrevious = true
    end
    
    -- Busca patrones específicos para tratamiento especial
    -- Detectar signos = (que serán visibles como -)
    local hasVisibleEquals = processedText:match("=") ~= nil
    
    -- Guardar posiciones donde hay signos = (para no eliminarlos después)
    local equalsPositions = {}
    local i = 1
    while true do
        i = string.find(processedText, "=", i)
        if i == nil then break end
        equalsPositions[i] = true
        i = i + 1
    end
    
    -- Procesamiento del texto para visualización
    
    -- Convertir = a - (estos guiones serán visibles)
    processedText = processedText:gsub("=", "-")
    
    -- Convertir =^ a -
    -- processedText = processedText:gsub("=^", "-")
    
    -- Eliminar todos los marcadores #
    processedText = processedText:gsub("#", "")
    
    -- Eliminar todos los marcadores ^
    processedText = processedText:gsub("%^", "")
    
    -- Eliminar todos los marcadores §
    processedText = processedText:gsub("%§", "_")
    
    -- Eliminar todos los símbolos +
    processedText = processedText:gsub("%+", "")
    
    -- Eliminar el nombre de la pista
    processedText = processedText:gsub("PART VOCALS", "")
    
    -- Eliminar el nombre del charter de la pista
    processedText = processedText:gsub("GHCripto", "") -- Omite el evento de texto de Copyright (de quien hizo el chart Vocal)
    
    -- Eliminar todo el texto entre corchetes, incluyendo los corchetes
    processedText = processedText:gsub("%[.-%]", "")
    
    -- Eliminar guiones originales (que no eran =)
    -- Hacer esto carácter por carácter para preservar los guiones que eran =
    local result = ""
    for j = 1, #processedText do
        local char = processedText:sub(j, j)
        if char == "-" and not equalsPositions[j] then
            -- Omitir guiones originales
        else
            result = result .. char
        end
    end
    processedText = result
    
    -- Elimina espacios extras que pudieran quedar después de eliminar el texto entre corchetes
    processedText = processedText:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    
    -- Crear y devolver la estructura de datos
    return {
        originalText = originalText,
        text = processedText,
        startTime = startTime,
        endTime = endTime,
        isActive = false,
        hasBeenSung = false,
        isToneless = hasTonelessMarker,
        -- Usar los resultados del análisis de conectores
        endsWithHyphen = connectsWithNext,
        beginsWithHyphen = connectsWithPrevious,
        pitch = pitch or 0,
        hasHeroPower = hasHeroPower or false  -- Hero Power
    }
end

-- Función para actualizar las letras en tiempo real
function updateVocals()
    if not showLyrics then
        return false
    end
    
    -- Verificar que hay un proyecto abierto
    if not isProjectOpen() then
        return false
    end
    
    -- Verificar validez de la pista PART VOCALS
    if not checkVocalsTrack() then
        -- Intentar encontrar la pista PART VOCALS
        if not findVocalsTrack() then
            return false
        end
    end
    
    -- Comprobar si hay cambios en la pista PART VOCALS
    local currentHash = ""
    
    -- Usar pcall para evitar errores
    local success, result = pcall(function()
        -- Recopilar un hash de todos los items MIDI en la pista PART VOCALS
        if vocalsTrack then
            local numItems = reaper.CountTrackMediaItems(vocalsTrack)
            for i = 0, numItems-1 do
                local item = reaper.GetTrackMediaItem(vocalsTrack, i)
                local take = reaper.GetActiveTake(item)
                
                if take and reaper.TakeIsMIDI(take) then
                    local _, hash = reaper.MIDI_GetHash(take, true)
                    currentHash = currentHash .. hash
                end
            end
        end
        
        -- Si el hash ha cambiado, necesitamos actualizar las letras
        if vocalsHash ~= currentHash then
            vocalsHash = currentHash
            return parseVocals() -- Analizar las letras de nuevo
        end
        
        return #phrases > 0
    end)
    
    -- En caso de error, devolver false
    if not success then
        return false
    end
    
    return result
end

-- Función para encontrar la pista PART VOCALS
function findVocalsTrack()
    vocalsTrack = findTrack("PART VOCALS")
    return vocalsTrack ~= nil
end

-- Función para parsear eventos de letras/Hero Power
function parseVocals()
    phrases = {}
    
    if not vocalsTrack then
        if not findVocalsTrack() then
            return false
        end
    end
    
    local numItems = reaper.CountTrackMediaItems(vocalsTrack)
    local currentHash = ""
    
    for i = 0, numItems-1 do
        local item = reaper.GetTrackMediaItem(vocalsTrack, i)
        local take = reaper.GetActiveTake(item)
        
        if reaper.TakeIsMIDI(take) then
            local _, hash = reaper.MIDI_GetHash(take, true)
            currentHash = currentHash .. hash
        end
    end
    
    if vocalsHash == currentHash and #phrases > 0 then
        return true  -- No hay cambios, usar las frases ya parseadas
    end
    
    vocalsHash = currentHash
    phrases = {}  -- Reiniciar frases
    
    for i = 0, numItems-1 do
        local item = reaper.GetTrackMediaItem(vocalsTrack, i)
        local take = reaper.GetActiveTake(item)
        
        if reaper.TakeIsMIDI(take) then
            -- Descomentar para depurar eventos
            -- debugTextEvents(take)
            
            local _, noteCount, _, textSysexCount = reaper.MIDI_CountEvts(take)
            -- reaper.ShowConsoleMsg("Item " .. i .. ": " .. noteCount .. " notas, " .. textSysexCount .. " eventos de texto\n")
            
            -- NUEVO: Recolectar todas las notas de Hero Power
            local heroPowerNotes = {}
            for n = 0, noteCount-1 do
                local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
                if pitch == HP then
                    local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
                    local noteEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
                    table.insert(heroPowerNotes, {startTime = noteStartTime, endTime = noteEndTime})
                end
            end
            
            -- Busca los marcadores de frases
            for j = 0, noteCount-1 do
                local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, j)
                local startTime = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
                local endTime = reaper.MIDI_GetProjQNFromPPQPos(take, endppq)
                
                if pitch == phraseMarkerNote then
                    table.insert(phrases, createPhrase(startTime, endTime))
                end
            end
            
            -- Si no hay marcadores de frase, crear una frase que abarque todo el ítem
            if #phrases == 0 then
                local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local startQN = reaper.TimeMap2_timeToQN(0, itemStart)
                local endQN = reaper.TimeMap2_timeToQN(0, itemEnd)
                table.insert(phrases, createPhrase(startQN, endQN))
                -- reaper.ShowConsoleMsg("Creada frase automática para todo el ítem\n")
            end
            
            -- NOTA: En Reaper, los eventos de texto de tipo "Letras"
            -- no necesariamente están asociados con notas. Se leerán directamente.
            local textEvents = {}
            for j = 0, textSysexCount-1 do
                local retval, selected, muted, ppqpos, type, msg = reaper.MIDI_GetTextSysexEvt(take, j)
                
                if retval and msg and msg ~= "" then
                    local time = reaper.MIDI_GetProjQNFromPPQPos(take, ppqpos)
                    local foundPitch = nil
                    local noteEndTime = time + 0.25  -- Duración predeterminada
                    
                    -- Buscar una nota MIDI que coincida con este evento de texto
                    for n = 0, noteCount-1 do
                        local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
                        local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
                        local nEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
                        
                        -- Si la nota no es un marcador de frase y coincide con el tiempo del evento
                        if pitch ~= phraseMarkerNote and math.abs(noteStartTime - time) < 0.01 then
                            foundPitch = pitch
                            noteEndTime = nEndTime
                            break
                        end
                    end
                    
                    table.insert(textEvents, {
                        text = msg,
                        time = time,
                        endTime = noteEndTime,
                        pitch = foundPitch
                    })
                end
            end
            
            -- Ordenar eventos de texto por tiempo
            table.sort(textEvents, function(a, b) return a.time < b.time end)
            
            -- Buscar notas asociadas a los eventos de texto para obtener duración
            for _, event in ipairs(textEvents) do
                for n = 0, noteCount-1 do
                    local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
                    local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
                    local noteEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
                    
                    -- Si la nota no es un marcador de frase y coincide con el tiempo del evento
                    if pitch ~= phraseMarkerNote and math.abs(noteStartTime - event.time) < 0.01 then
                        event.endTime = noteEndTime
                        break
                    end
                end
            end
            
            -- Asignar eventos de texto a frases
            for _, event in ipairs(textEvents) do
                local assignedToPhrase = false
                
                for k, phrase in ipairs(phrases) do
                    if event.time >= phrase.startTime and event.time <= phrase.endTime then
                        -- MODIFICADO: Comprobar si este evento coincide con alguna nota Hero Power
                        local hasHeroPower = false
                        for _, hpNote in ipairs(heroPowerNotes) do
                            -- Comprobar si el evento está dentro del rango de la nota Hero Power
                            -- o muy cercano a su inicio (con un margen de tolerancia mayor)
                            if (event.time >= hpNote.startTime and event.time <= hpNote.endTime) or
                               math.abs(event.time - hpNote.startTime) < 0.03 then
                                hasHeroPower = true
                                break
                            end
                        end
                        
                        table.insert(phrase.lyrics, createLyric(
                            event.text,
                            event.time,
                            event.endTime,
                            event.pitch,
                            hasHeroPower  -- Pasar el flag de Hero Power
                        ))
                        assignedToPhrase = true
                        break
                    end
                end
                
                -- Si no se asignó a ninguna frase, crear una nueva frase
                if not assignedToPhrase and #phrases > 0 then
                    -- Asignar al más cercano
                    local closestPhrase = 1
                    local minDistance = math.huge
                    
                    for k, phrase in ipairs(phrases) do
                        local distance = math.min(
                            math.abs(event.time - phrase.startTime),
                            math.abs(event.time - phrase.endTime)
                        )
                        
                        if distance < minDistance then
                            minDistance = distance
                            closestPhrase = k
                        end
                    end
                    
                    -- MODIFICADO: Comprobar si este evento coincide con alguna nota Hero Power
                    local hasHeroPower = false
                    for _, hpNote in ipairs(heroPowerNotes) do
                        -- Comprobar si el evento está dentro del rango de la nota Hero Power
                        -- o muy cercano a su inicio (con un margen de tolerancia mayor)
                        if (event.time >= hpNote.startTime and event.time <= hpNote.endTime) or
                           math.abs(event.time - hpNote.startTime) < 0.03 then
                            hasHeroPower = true
                            break
                        end
                    end
                    
                    table.insert(phrases[closestPhrase].lyrics, createLyric(
                        event.text,
                        event.time,
                        event.endTime,
                        event.pitch,
                        hasHeroPower  -- Pasar el flag de Hero Power
                    ))
                end
            end
        end
    end
    
    -- Ordenar las letras dentro de cada frase por tiempo de inicio
    for k, phrase in ipairs(phrases) do
        table.sort(phrase.lyrics, function(a, b) return a.startTime < b.startTime end)
        -- reaper.ShowConsoleMsg("Frase " .. k .. ": " .. #phrase.lyrics .. " eventos de texto\n")
    end
    
    -- Ordenar las frases por tiempo de inicio
    table.sort(phrases, function(a, b) return a.startTime < b.startTime end)
    
    return #phrases > 0
end

-- Función para actualizar el estado activo de las letras basado en el tiempo actual
function updateLyricsActiveState(currentTime)
    -- Encontrar la frase actual
    currentPhrase = 1
    for i, phrase in ipairs(phrases) do
        if currentTime >= phrase.startTime then
            currentPhrase = i
        end
    end
    
    -- Actualizar todas las letras en todas las frases
    for _, phrase in ipairs(phrases) do
        for i, lyric in ipairs(phrase.lyrics) do
            -- Una letra está activa normalmente si el tiempo actual está entre su inicio y fin
            local isCurrentlyActive = (currentTime >= lyric.startTime and currentTime <= lyric.endTime)
            
            -- Comprobar si hay que extender el tiempo activo debido a signos +
            local extendedActive = false
            local extendedEndTime = lyric.endTime
            
            -- Buscar hacia adelante para encontrar todos los + consecutivos
            local j = i + 1
            while j <= #phrase.lyrics do
                local nextLyric = phrase.lyrics[j]
                -- Si la siguiente letra comienza con +, extender la activación
                if nextLyric.originalText:find("^%+") then
                    extendedEndTime = nextLyric.endTime
                    -- Extender el tiempo activo hasta incluir este +
                    if currentTime >= lyric.startTime and currentTime <= extendedEndTime then
                        extendedActive = true
                    end
                    j = j + 1  -- Seguir buscando más +
                else
                    break  -- No hay más + consecutivos
                end
            end
            
            -- La letra está activa si cumple los criterios normales o la extensión de los +
            lyric.isActive = isCurrentlyActive or extendedActive
            
            -- Una letra está cantada si ya pasó su tiempo final extendido
            lyric.hasBeenSung = (currentTime > extendedEndTime)
            
            -- Caso especial: si una letra está activa, no está cantada todavía
            if lyric.isActive then
                lyric.hasBeenSung = false
            end
            
            -- Las letras que son + no deben mostrar su propio estado activo
            -- ya que ese tiempo lo absorbe la letra anterior
            if lyric.originalText:find("^%+") then
                if i > 1 and phrase.lyrics[i-1].isActive then
                    lyric.isActive = true  -- heredar estado activo si la anterior está activa
                end
            end
        end
    end
end

-- Configuración para las líneas de notas (márgenes independientes y rewind correcto)
local noteLineConfig = {
    -- Colores
    activeColor              = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},  -- Color de notas activas (FRASES COMPLETAS)
    inactiveColor            = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},  -- Color de notas inactivas (FRASES COMPLETAS)
    sungColor                = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},  -- Color de notas ya cantadas (pasado)
    hitColor                 = {r = 1.0, g = 1.0, b = 0.3, a = 1.0},  -- Color de notas siendo cantadas (presente)
    hitLineColor             = {r = 1.0, g = 1.0, b = 1.0, a = 1.0},  -- Color blanco de la línea vertical de golpe
    hitLineThickness         = 3,    -- Grosor en píxeles de la línea
    hitLineFadePct           = 0.45, -- Porcentaje de la altura total para el degradado (0.25 = 25%)
    linesSpacing             = 8,   -- Espaciado vertical en pixeles de las líneas de las notas
    specialNoteRadius        = 10,   -- Tamaño del círculo de las notas sin tono
    specialNoteYOffset       = 0,    -- Desplazamiento vertical de notas sin tono. 0 = Default, Positivo = arriba, Negativo = abajo
    noteThickness            = 2,    -- Grosor en píxeles de las líneas de las notas y sus conectores
    noteLineStyle            = "default", -- Estilo de las líneas. Opciones: "default", "offset_top", "offset_bottom"

    -- Rango absoluto de pitch
    minPitch                 = 32,   -- Nora mínima del "mundo" del HUD
    maxPitch                 = 87,   -- Nora máxima del "mundo" del HUD

    -- Dimensiones HUD
    areaHeight               = 150,  -- Altura del hud
    yOffset                  = 0,    -- Posición vertical del HUD; NO TOCAR!!!!!!
    hitLineX                 = 150,  -- Posición horizontal de la línea de golpe
    hitCircleRadius          = 10,   -- tamaño del círculo de la línea de golpe
    hitCircleYOffset         = 1,    -- Desplazamiento vertical del círculo de golpe. 0 = Default, Positivo = arriba, Negativo = abajo

    -- Dinámica de zoom
    dynamicPitchRange        = true, -- Activar/Desactivar el HUD dinámico
    minimumZoomRange         = 18.0, -- Zoom máximo (Rango de notas a mostrar)
    panZoomSpeed             = 9.0,  -- Suavidad de la cámara (Velocidad de la animación)
    panZoomBaseSpeed         = 1.5,  -- Velocidad base para el panZoomSpeed. Mayor valor, más velocidad ( 1.5 = GHL)
    vocalScrollSpeed         = 1.1,  -- Velocidad del desplazamiento de las notas. Mayor valor, más velocidad
    vocalScrollSpeedBase     = 295,  -- Velocidad base de las notas en píxeles por segundo (295: GHL)

    -- Márgenes independientes en píxeles
    pixelMarginTop           = 24.5,   -- Padding superior en pixeles del área segura del HUD
    pixelMarginBottom        = 36.5,   -- Padding inferior en pixeles del área segura del HUD
    showPaddingLines         = false,  -- Activar/Desactivar líneas del padding de pixeles (solo números impares)
    paddingLineThickness     = 3,      -- Grosor en píxeles (solo números impares)
    paddingLineColor         = {r = 1.0, g = 0.3, b = 0.3, a = 1.0}, -- Rojo semitransparente

    -- Tiempo real (segundos)
    viewFutureSec            = 4.0,  -- Mirar al futuro en segundos para recalcular
    viewPastSec              = 1.5,  -- Mirar al pasado en segundos para mantener
    jumpThresholdSec         = 0.5,  -- Detector de saltos para recalcular

    -- Estados internos
    currentMinDisplayPitch   = 53.0, -- Dónde está la cámara
    currentMaxDisplayPitch   = 67.0, -- Dónde está la cámara
    targetMinDisplayPitch    = 53.0, -- A dónde quiere ir cámara
    targetMaxDisplayPitch    = 67.0, -- A dónde quiere ir cámara
    _lastTimeSec             = -1000.0, -- (Memoria interna) Último tiempo de reproducción conocido
    _lastRecalcTimeSec       = -1000.0, -- (Memoria interna) Último tiempo en que se recalculó el zoom/paneo
    
    -- TABLA DE RANGOS (GHL)
    staticRanges = {
        -- Ordenamos de la zona más baja a la más alta
        { min = 32, max = 45 },
        { min = 39, max = 52 },
        { min = 46, max = 60 },
        { min = 53, max = 67 }, -- Cámara por defecto (GHL)
        { min = 54, max = 65 },
        { min = 59, max = 73 },
        -- { min = 64, max = 74 }, -- Nuevo rango adicional
        -- { min = 65, max = 77 }, -- Nuevo rango adicional
        { min = 67, max = 80 },
        { min = 74, max = 87 },
    },

    -- Líneas del pentagrama
    ghlGuideLines = {
        stave1 = {43, 47, 50, 53, 57}, -- Pentagrama grave
        stave2 = {64, 67, 71, 74, 77}, -- Pentagrama agudo
    },
    referencePitchIntervalForSpacing = 3, -- El intervalo de pitch que define el espaciado visual estándar (NO TOCAR!!!!)
    staffLinePaddingTop      = 19,     -- Píxeles de margen superior para las líneas | TEST: 27.4
    staffLinePaddingBottom   = 24,     -- Píxeles de margen inferior para las líneas | TEST: 34.6
    staffLineThickness       = 2,      -- Grosor en pixeles (2 en GH, 1 por defecto)
    staffLineYOffset         = 0,      -- Desplazamiento vertical. 0 = Default, Positivo = arriba, Negativo = abajo
    ghlGuideLineAlpha        = 0.1,    -- Opacidad de las líneas guia
}

-- Función auxiliar para encontrar la mejor zona estática para un rango de notas
local function findBestStaticRange(minP, maxP)
    local c = noteLineConfig
    -- Busca la primera zona estática donde quepan las notas
    for _, zone in ipairs(c.staticRanges) do
        if minP >= zone.min and maxP <= zone.max then
            return zone -- Devuelve la tabla completa de la zona
        end
    end
    return nil -- No se encontró ninguna zona adecuada
end

-- Recalcula el rango objetivo con una nueva lógica híbrida
local function recalcTargetPitchRange(currentTimeSec, noteList, deltaTime)
    local c = noteLineConfig
    
    local isRewind = deltaTime and deltaTime < 0
    local isForwardJump = deltaTime and deltaTime > c.jumpThresholdSec
    local forceRecalc = isRewind or isForwardJump or (c._lastRecalcTimeSec and currentTimeSec < c._lastRecalcTimeSec)

    -- Ventana de tiempo para analizar las notas futuras
    local startT = currentTimeSec - c.viewPastSec
    local endT   = currentTimeSec + c.viewFutureSec

    -- Encontrar el rango de tono/pitch de las notas en la ventana de tiempo
    local minPf, maxPf = math.huge, -math.huge
    for _, n in ipairs(noteList) do
        if n.time >= startT and n.time <= endT then
            -- Ignora las notas especiales (26, 29, y sin tono "#") para el cálculo del zoom/paneo (como en GHL)
            if n.pitch > 0 and n.pitch ~= 26 and n.pitch ~= 29 and not n.isToneless then
                minPf = math.min(minPf, n.pitch)
                maxPf = math.max(maxPf, n.pitch)
            end
        end
    end

    -- Si no hay notas futuras, no hay por qué mover la cámara.
    if minPf == math.huge then return end

    local minP = math.max(minPf, c.minPitch)
    local maxP = math.min(maxPf, c.maxPitch)
    
    -- ESTABILIDAD: Si las notas ya caben en la vista actual, no hacer nada
    if not forceRecalc and minP >= c.currentMinDisplayPitch and maxP <= c.currentMaxDisplayPitch then
        return
    end
    
    -- Si se llega hasta aquí, la cámara debe moverse
    c._lastRecalcTimeSec = currentTimeSec
    
    -- LÓGICA HÍBRIDA

    -- Intentar encontrar una ZONA ESTÁTICA perfecta
    local bestZone = findBestStaticRange(minP, maxP)
    
    if bestZone then
        -- Si encuentra una zona de reposo, el objetivo será esa zona
        c.targetMinDisplayPitch = bestZone.min
        c.targetMaxDisplayPitch = bestZone.max
    else
        -- MODO EMERGENCIA: Si no cabe en ninguna zona, activar el ZOOM DINÁMICO
        local actualNotesSpan = maxP - minP
        
        -- El tamaño de la vista será el del rango de notas, pero NUNCA menor que minimumZoomRange
        local finalSpanToShow = math.max(actualNotesSpan, c.minimumZoomRange)
        
        -- Centrar la cámara en el punto medio de las notas
        local midP = (minP + maxP) / 2
        c.targetMinDisplayPitch = midP - finalSpanToShow / 2
        c.targetMaxDisplayPitch = midP + finalSpanToShow / 2
    end
end

-- Interpola suavemente la cámara, pero con una parada controlada
local function updateDisplayPitchRange(deltaTime)
    local c = noteLineConfig
    
    -- Definir un umbral de proximidad. No deja que la cámara llegue al 100% del objetivo
    local minimumDistance = 0.001

    -- Calcular la distancia que falta para llegar al target
    local minDiff = c.targetMinDisplayPitch - c.currentMinDisplayPitch
    local maxDiff = c.targetMaxDisplayPitch - c.currentMaxDisplayPitch

    -- Calcular la velocidad final de la cámara
    local speed = c.panZoomBaseSpeed * c.panZoomSpeed
    
    -- Si el tiempo se detiene o va hacia atrás, asume un framerate de 60fps para que no se pare
    if deltaTime <= 0 then deltaTime = 1/60 end
    
    -- Máximo movimiento permitido para este frame
    local maxMovement = speed * deltaTime

    -- --- Lógica principal del movimiento ---
    
    -- Mover el Min Pitch:
    -- Esto comprueba si el movimiento de este frame pasaría del umbral de parada
    if math.abs(minDiff) <= maxMovement + minimumDistance then
        -- Si es así, no salta al final. Posiciona la cámara justo a `minimumDistance` del objetivo
        local direction = minDiff > 0 and 1 or -1
        c.currentMinDisplayPitch = c.targetMinDisplayPitch - (minimumDistance * direction)
    else
        -- Si no, realiza el movimiento lineal normal
        local direction = minDiff > 0 and 1 or -1
        c.currentMinDisplayPitch = c.currentMinDisplayPitch + (direction * maxMovement)
    end
    
    -- Mover el Max Pitch:
    if math.abs(maxDiff) <= maxMovement + minimumDistance then
        local direction = maxDiff > 0 and 1 or -1
        c.currentMaxDisplayPitch = c.targetMaxDisplayPitch - (minimumDistance * direction)
    else
        local direction = maxDiff > 0 and 1 or -1
        c.currentMaxDisplayPitch = c.currentMaxDisplayPitch + (direction * maxMovement)
    end
end

-- Convierte frases a lista de notas
local function phrasesToNotes(phrases)
    local out = {}
    for _, ph in ipairs(phrases) do
        for _, ly in ipairs(ph.lyrics) do
            if ly.pitch and ly.pitch > 0 then
                local t = reaper.TimeMap2_beatsToTime(0, ly.startTime)
                -- Propiedad 'isToneless' agregada para que la use la función de cálculo del HUD
                table.insert(out, {time = t, pitch = ly.pitch, isToneless = ly.isToneless})
            end
        end
    end
    return out
end

-- Función principal del HUD vocal
function drawLyricsVisualizer()
    if #phrases == 0 then
        return
    end

    -- Función auxiliar que calcula la posición Y de un pitch usando una escala puramente lineal
    -- Esta es la base para anclar los pentagramas

    local function getLinearYPosition(pitch, config, calculatePaddedY)
        local currentMinP = config.currentMinDisplayPitch
        local currentMaxP = config.currentMaxDisplayPitch
        local pitchRangeSize = currentMaxP - currentMinP
        if pitchRangeSize <= 0 then
            return -1000
        end

        local normalizedPitch = (pitch - currentMinP) / pitchRangeSize
        return calculatePaddedY(normalizedPitch)
    end

    -- Calcula la coordenada Y precisa para una nota MIDI, alineándola con
    -- las líneas del pentagrama usando un espaciado visual estándar y consistente (muy similar a GHL)

    local function getNoteYPosition(pitch, config, calculatePaddedY)
        -- Calcula el espaciado en píxeles estándar basado en el intervalo de referencia
        local refInterval = config.referencePitchIntervalForSpacing or 3
        local y1 = getLinearYPosition(config.currentMinDisplayPitch, config, calculatePaddedY)
        local y2 = getLinearYPosition(config.currentMinDisplayPitch + refInterval, config, calculatePaddedY)
        local pixel_step_y = math.abs(y1 - y2)

        local targetStave = nil
        if pitch >= config.ghlGuideLines.stave1[1] and pitch <= config.ghlGuideLines.stave1[#config.ghlGuideLines.stave1] then
            targetStave = config.ghlGuideLines.stave1
        elseif pitch >= config.ghlGuideLines.stave2[1] and pitch <= config.ghlGuideLines.stave2[#config.ghlGuideLines.stave2] then
            targetStave = config.ghlGuideLines.stave2
        end

        -- CASO 1: LA NOTA ESTÁ DENTRO DE UN PENTAGRAMA GUÍA
        if targetStave then
            -- Anclar el pentagrama usando la posición lineal de su primera nota.
            local anchorY = getLinearYPosition(targetStave[1], config, calculatePaddedY)

            -- Encontrar el índice de la línea guía más cercana por debajo
            local base_line_index = 1
            for i = 1, #targetStave do
                if targetStave[i] <= pitch then
                    base_line_index = i
                else
                    break
                end
            end
            
            -- Calcular la posición desde el ancla usando el paso estándar de píxeles
            local baseLineY = anchorY - ((base_line_index - 1) * pixel_step_y)

            -- Interpolar finamente si la nota está entre dos líneas guía
            if base_line_index < #targetStave then
                local lower_p = targetStave[base_line_index]
                local upper_p = targetStave[base_line_index + 1]
                local pitch_interval = upper_p - lower_p
                
                if pitch_interval > 0 then
                    local factor = (pitch - lower_p) / pitch_interval
                    local y_offset = factor * pixel_step_y
                    return baseLineY - y_offset
                end
            end
            
            return baseLineY
        
        -- CASO 2: LA NOTA ESTÁ FUERA DE CUALQUIER PENTAGRAMA GUÍA (Fallback)
        else
            -- Para notas que no pertenecen a un pentagrama (como entre 57 y 64), se usa el método lineal
            return getLinearYPosition(pitch, config, calculatePaddedY)
        end
    end

    local currentTimeSec = reaper.TimeMap2_beatsToTime(0, curBeat)
    local deltaTime      = currentTimeSec - (noteLineConfig._lastTimeSec or currentTimeSec)
    noteLineConfig._lastTimeSec = currentTimeSec

    recalcTargetPitchRange(currentTimeSec, phrasesToNotes(phrases), deltaTime)
    
    updateDisplayPitchRange(deltaTime)

    -- Calcular posición y dimensiones para el visualizador de letras con los nuevos valores
    local visualizerHeight = lyricsConfig.height
    local visualizerY = gfx.h - visualizerHeight - 40 + lyricsConfig.bottomMargin

    -- Posición vertical del HUD
    noteLineConfig.yOffset = visualizerY - 30

    -- Límite virtual, PADDING al HUD
    local function calculatePaddedY(pitchNormalized)
        local c = noteLineConfig
        -- Asegurar que los márgenes existen para evitar errores, si no, usar 0
        local marginTop = c.pixelMarginTop or 0
        local marginBottom = c.pixelMarginBottom or 0
        
        -- Calcula la altura real disponible para las notas, restando los márgenes
        local effectiveHeight = c.areaHeight - marginTop - marginBottom
        
        -- Si la altura efectiva es negativa (márgenes más grandes que el área), clampear a 0
        if effectiveHeight < 0 then
            effectiveHeight = 0
        end
        
        -- Calcula el offset vertical dentro del área efectiva
        local pitchOffset = effectiveHeight * pitchNormalized
        
        -- Posición final
        return c.yOffset - (marginBottom + pitchOffset)
    end
    
    -- Dibujar fondo para el visualizador con opacidad ajustada
    gfx.r, gfx.g, gfx.b, gfx.a = 0.1, 0.1, 0.15, lyricsConfig.bgOpacity
    gfx.rect(0, visualizerY - 30, gfx.w, visualizerHeight + 40, 1)
    
    -- Encontrar la frase actual y la siguiente
    local currentPhraseObj = phrases[currentPhrase]
    local nextPhraseObj = currentPhrase < #phrases and phrases[currentPhrase + 1] or nil
    
    -- Solo dibujar el HUD de notas si está activado
    if showNotesHUD then
        -- Dibujar fondo para las líneas de notas
        gfx.r, gfx.g, gfx.b, gfx.a = 0.1, 0.1, 0.15, 0.8
        gfx.rect(0, noteLineConfig.yOffset - noteLineConfig.areaHeight, gfx.w, noteLineConfig.areaHeight, 1)

        -- Dibujar líneas del PADDING
        if noteLineConfig.showPaddingLines then
            local c = noteLineConfig

            -- Establecer el color para las líneas de padding
            gfx.r, gfx.g, gfx.b, gfx.a = c.paddingLineColor.r, c.paddingLineColor.g, c.paddingLineColor.b, c.paddingLineColor.a
            
            -- Calcular la posición Y de la línea SUPERIOR
            local topLineY = (c.yOffset - c.areaHeight) + (c.pixelMarginTop or 0)

            -- Calcular la posición Y de la línea INFERIOR
            local bottomLineY = c.yOffset - (c.pixelMarginBottom or 0)
            
            -- Grosor del PADDING
            local thickness = c.paddingLineThickness or 1
            -- Se calcula el offset para el bucle: Si el grosor es 3, el bucle irá de -1 a 1
            local offset = math.floor((thickness - 1) / 2) 

            for i = -offset, offset do
                -- Dibujar ambas líneas con el offset vertical 'i'
                gfx.line(0, topLineY + i, gfx.w, topLineY + i, 1)
                gfx.line(0, bottomLineY + i, gfx.w, bottomLineY + i, 1)
            end
            
            -- Restaura el alpha, esto evita que afecte a los demás dibujos
            gfx.a = 1.0
        end

        -- Función para dibujar un PENTAGRAMA con espaciado estándar y consistente
        local function drawStandardSpacedStaff(stave, config, calculatePaddedY)
            if not stave or #stave < 2 then
                return
            end

            -- LEER EL OFFSET (o usar 0 si no está definido)
            -- La inversión del signo ocurre aquí para que positivo sea arriba.
            local yOffset = -(config.staffLineYOffset or 0)

            -- Calcular el espaciado en píxeles estándar basado en el intervalo de referencia
            local refInterval = config.referencePitchIntervalForSpacing or 3
            local y1 = getLinearYPosition(config.currentMinDisplayPitch, config, calculatePaddedY)
            local y2 = getLinearYPosition(config.currentMinDisplayPitch + refInterval, config, calculatePaddedY)
            local pixel_step_y = math.abs(y1 - y2)

            -- Anclar el pentagrama usando la posición lineal de su primera nota
            -- APLICAR EL OFFSET AL ANCLA
            local anchorY = getLinearYPosition(stave[1], config, calculatePaddedY) + yOffset
            
            local thickness = config.staffLineThickness or 1
            local rectY_offset = math.floor(thickness / 2)  -- Para centrar la línea
            local clipTopY = (config.yOffset - config.areaHeight) + (config.staffLinePaddingTop or 0)
            local clipBottomY = config.yOffset - (config.staffLinePaddingBottom or 0)

            -- Dibujar cada línea a partir del ancla usando el paso de píxeles estándar
            for i = 1, #stave do
                -- La primera línea está en anchorY; Las siguientes se espacian uniformemente
                local lineY = anchorY - ((i - 1) * pixel_step_y)
                
                if lineY >= clipTopY and lineY <= clipBottomY then
                    -- Calcular la posición Y del rectángulo considerando el grosor
                    local rectY = lineY - rectY_offset
                    -- Dibujar la línea como un rectángulo con el grosor especificado
                    gfx.rect(0, rectY, gfx.w, thickness, 1)
                end
            end
        end

        -- Preparar para dibujar las líneas guía
        gfx.r, gfx.g, gfx.b = 1.0, 1.0, 1.0
        gfx.a = noteLineConfig.ghlGuideLineAlpha
        
        -- Dibujar ambos pentagramas de forma independiente con la nueva lógica de espaciado estándar
        drawStandardSpacedStaff(noteLineConfig.ghlGuideLines.stave1, noteLineConfig, calculatePaddedY)
        drawStandardSpacedStaff(noteLineConfig.ghlGuideLines.stave2, noteLineConfig, calculatePaddedY)

        gfx.a = 1.0 -- Restaurar alpha para los siguientes dibujos

        -- Efecto Fade vertical para la línea de golpe (como en GHL)
        local c = noteLineConfig
        local topY = c.yOffset - c.areaHeight
        local bottomY = c.yOffset
        
        -- Asegurarse de que los nuevos parámetros existan para evitar errores
        local thickness = c.hitLineThickness or 3

        -- El tamaño del fade se calcula basado en el porcentaje de la altura total
        local fadeHeight = c.areaHeight * (c.hitLineFadePct or 0.25)
        local color = c.hitLineColor or {r = 1.0, g = 0.3, b = 0.3, a = 1.0}

        -- Calcular la posición X de inicio para centrar la línea
        local startX = c.hitLineX - math.floor(thickness / 2)

        -- Establecer el color base de la línea
        gfx.r, gfx.g, gfx.b = color.r, color.g, color.b

        -- Iterar verticalmente, píxel por píxel, para dibujar la línea con degradado
        for y = topY, bottomY do
            -- Calcular la distancia al borde más cercano (superior o inferior)
            local distFromTop = y - topY
            local distFromBottom = bottomY - y
            local distToEdge = math.min(distFromTop, distFromBottom)
            
            -- Calcular el alfa basado en la distancia al borde
            local finalAlpha
            if distToEdge < fadeHeight and fadeHeight > 0 then
                -- Si estamos en la zona de degradado, calcular el alfa proporcionalmente
                finalAlpha = distToEdge / fadeHeight
            else
                -- Si estamos en la zona central, el alfa es 1 (sólido)
                finalAlpha = 1.0
            end
            
            -- Aplicar el alfa calculado, multiplicado por el alfa base del color
            gfx.a = color.a * finalAlpha
            
            -- Dibujar un pequeño rectángulo de 1 píxel de alto para este segmento de la línea
            gfx.rect(startX, y, thickness, 1, 1)
        end
        gfx.a = 1.0 -- Restaurar el alfa para los siguientes dibujos
        
        -- Variable para rastrear si hay alguna nota activa cruzando la línea de golpeo
        local hitDetected = false
        local hitY = 0
        
        -- Función para dibujar líneas de notas para una frase
        local function drawNoteLines(phrase, opacity)
            if not phrase then
                return
            end
            
            -- Variables para rastrear la letra anterior
            local prevLyric = nil
            local prevEndX = nil
            local prevLineY = nil
            local prevUpperLineY = nil
            local prevLowerLineY = nil
            
            -- Variables para detectar primera y última nota de la frase
            local firstNoteIndex = nil
            local lastNoteIndex = nil
            
            -- Encontrar la primera y última nota con pitch en la frase
            for i, lyric in ipairs(phrase.lyrics) do
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    if not firstNoteIndex then
                        firstNoteIndex = i
                    end
                    lastNoteIndex = i
                end
            end
            
            -- Primera pasada: identificar las cadenas de notas conectadas
            local connectChains = {} -- Para rastrear las cadenas completas de notas conectadas
            local chainIds = {} -- Para asignar un ID único a cada cadena
            local nextChainId = 1
            
            -- Construir las cadenas de notas conectadas
            for i, lyric in ipairs(phrase.lyrics) do
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    if lyric.originalText:match("^%+") then
                        -- SI esta es una nota conectora, buscar su nota anterior
                        local foundPrev = false
                        for j = i-1, 1, -1 do
                            if phrase.lyrics[j].pitch and phrase.lyrics[j].pitch > 0 then
                                -- Encontramos la nota anterior que está conectada a esta
                                foundPrev = true
                                
                                -- Verificar si la nota anterior ya pertenece a una cadena
                                if chainIds[j] then
                                    -- Añadir esta nota a la cadena existente
                                    chainIds[i] = chainIds[j]
                                    table.insert(connectChains[chainIds[j]], i)
                                else
                                    -- Crear una nueva cadena con ambas notas
                                    chainIds[j] = nextChainId
                                    chainIds[i] = nextChainId
                                    connectChains[nextChainId] = {j, i}
                                    nextChainId = nextChainId + 1
                                end
                                break
                            end
                        end
                    end
                end
            end
            
            -- Determinar qué cadenas deben iluminarse
            local shouldHighlight = {}
            local chainsToHighlight = {}
            
            -- Primero, verificar qué cadenas tienen al menos un elemento activo
            for i, lyric in ipairs(phrase.lyrics) do
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then

                    -- Lógica de velocidad en pixeles para las notas
                    local speed = (noteLineConfig.vocalScrollSpeedBase or 200) * (noteLineConfig.vocalScrollSpeed or 1.0)
                    local startTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                    local endTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                    local timeDiffStart = startTimeSec - currentTimeSec
                    local timeDiffEnd = endTimeSec - currentTimeSec
                    local startX = noteLineConfig.hitLineX + (timeDiffStart * speed)
                    local endX = noteLineConfig.hitLineX + (timeDiffEnd * speed)
                    
                    -- Si esta nota está activa (sin importar si cruza el recogedor)
                    if lyric.isActive then
                        if chainIds[i] then
                            -- Marcar toda esta cadena para iluminar
                            chainsToHighlight[chainIds[i]] = true
                        else
                            -- Si es una nota individual, iluminarla si cruza el recogedor
                            if startX <= noteLineConfig.hitLineX and endX >= noteLineConfig.hitLineX then
                                shouldHighlight[i] = true
                            end
                        end
                    end
                end
            end
            
            -- Marcar todas las notas de las cadenas que deben iluminarse
            for chainId, highlight in pairs(chainsToHighlight) do
                if highlight then
                    for _, noteIndex in ipairs(connectChains[chainId]) do
                        shouldHighlight[noteIndex] = true
                    end
                end
            end
            
            -- Para notas que ya pasaron el recogedor pero están en una cadena activa
            for chainId, chain in pairs(connectChains) do
                -- Verificar si al menos una nota de la cadena está activa
                local chainActive = false
                for _, noteIndex in ipairs(chain) do
                    local lyric = phrase.lyrics[noteIndex]
                    if lyric.isActive then
                        chainActive = true
                        break
                    end
                end
                
                -- Si la cadena está activa, iluminar todas las notas incluso las que ya pasaron
                if chainActive then
                    for _, noteIndex in ipairs(connectChains[chainId]) do
                        shouldHighlight[noteIndex] = true
                    end
                end
            end
            
            for i, lyric in ipairs(phrase.lyrics) do
                -- Solo dibujar si tiene pitch (tono) y no es sin tono
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    local lineY
                    if lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless then
                        lineY = calculatePaddedY(0.5)
                    else
                        lineY = getNoteYPosition(lyric.pitch, noteLineConfig, calculatePaddedY)
                    end
                    
                    -- Define los límites superior e inferior del área de dibujado de notas
                    local topBoundaryY = (noteLineConfig.yOffset - noteLineConfig.areaHeight) + (noteLineConfig.pixelMarginTop or 0)
                    local bottomBoundaryY = noteLineConfig.yOffset - (noteLineConfig.pixelMarginBottom or 0)

                    -- Esto asegura que lineY nunca se calcule fuera de estos límites para el dibujado
                    lineY = math.max(topBoundaryY, math.min(bottomBoundaryY, lineY))
                    
                    -- Lógica de velocidad en pixeles para las notas
                    local speed = (noteLineConfig.vocalScrollSpeedBase or 200) * (noteLineConfig.vocalScrollSpeed or 1.0)
                    local startTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                    local endTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                    local timeDiffStart = startTimeSec - currentTimeSec
                    local timeDiffEnd = endTimeSec - currentTimeSec
                    local startX = noteLineConfig.hitLineX + (timeDiffStart * speed)
                    local endX = noteLineConfig.hitLineX + (timeDiffEnd * speed)
                    
                    -- Limitar a la ventana visible
                    local originalStartX = startX  -- Esto guarda el valor original antes de limitarlo
                    local originalEndX = endX
                    startX = math.max(150, math.min(gfx.w, startX))
                    endX = math.max(20, math.min(gfx.w, endX))
                    
                    -- Determinar si esta nota está visible
                    local isVisible = (endX > 20 and startX < gfx.w)
                    
                    -- Verificar si la nota está tocando la línea de golpeo
                    local isHitting = (originalStartX <= noteLineConfig.hitLineX and originalEndX >= noteLineConfig.hitLineX and lyric.isActive)
                    
                    -- Verificar si esta nota debe iluminarse debido a una nota conectora
                    local shouldIlluminate = isHitting or shouldHighlight[i] or false
                    
                    -- Solo dibujar si la línea es visible
                    if isVisible then
                        -- Define el color según el estado de la nota
                        if shouldIlluminate then
                            -- Nota en una cadena activa o golpeando la línea - usar color de efecto de golpeo
                            gfx.r = noteLineConfig.hitColor.r
                            gfx.g = noteLineConfig.hitColor.g
                            gfx.b = noteLineConfig.hitColor.b
                            gfx.a = noteLineConfig.hitColor.a * opacity
                            
                            -- Solo registrar el golpe y su posición "Y" si realmente está tocando el recogedor
                            if isHitting then
                                hitDetected = true
                                hitY = lineY
                            end
                        elseif lyric.isActive then
                            gfx.r = noteLineConfig.activeColor.r
                            gfx.g = noteLineConfig.activeColor.g
                            gfx.b = noteLineConfig.activeColor.b
                            gfx.a = noteLineConfig.activeColor.a * opacity
                        elseif lyric.hasBeenSung then
                            gfx.r = noteLineConfig.sungColor.r
                            gfx.g = noteLineConfig.sungColor.g
                            gfx.b = noteLineConfig.sungColor.b
                            gfx.a = noteLineConfig.sungColor.a * opacity
                        else
                            gfx.r = noteLineConfig.inactiveColor.r
                            gfx.g = noteLineConfig.inactiveColor.g
                            gfx.b = noteLineConfig.inactiveColor.b
                            gfx.a = noteLineConfig.inactiveColor.a * opacity
                        end
                        
                        -- Calcular las posiciones Y para las líneas superior e inferior, aplicando el estilo de offset (como en GHL, líneas perfectamente alineadas)
                        local upperLineY = lineY - noteLineConfig.linesSpacing/2
                        local lowerLineY = lineY + noteLineConfig.linesSpacing/2
                        
                        if noteLineConfig.noteLineStyle == "offset_top" then
                            upperLineY = upperLineY + 1
                        elseif noteLineConfig.noteLineStyle == "offset_bottom" then
                            lowerLineY = lowerLineY + 1
                        end

                        -- Solo dibujar la parte de las líneas que están a la derecha del recogedor
                        local visibleStartX = math.max(startX, noteLineConfig.hitLineX)
                        
                        -- Solo dibujar si al menos parte de la nota está a la derecha del recogedor
                        if endX > noteLineConfig.hitLineX then
                            -- Comprobar si es una nota especial (pitch 26 o 29)
                            if lyric.pitch == 29 then
                                -- Nota 29: Dibujar solo un círculo
                                local circleRadius = noteLineConfig.specialNoteRadius
                                local yOffset = noteLineConfig.specialNoteYOffset or 0
                                local finalCircleY = lineY - yOffset -- Restamos para que positivo sea arriba

                                if startX >= noteLineConfig.hitLineX then
                                    gfx.circle(startX, finalCircleY, circleRadius, 1, 1)
                                elseif endX > noteLineConfig.hitLineX then
                                    gfx.circle(noteLineConfig.hitLineX, finalCircleY, circleRadius, 1, 1)
                                end
                            elseif lyric.pitch == 26 or lyric.isToneless then
                                -- Nota 26: Dibujar círculo al inicio y líneas normales
                                local circleRadius = noteLineConfig.specialNoteRadius
                                local noteThickness = noteLineConfig.noteThickness or 1
                                local yOffsetRect = math.floor(noteThickness / 2)

                                -- Las líneas rectangulares se quedan en su sitio original
                                gfx.rect(visibleStartX, upperLineY - yOffsetRect, endX - visibleStartX + 1, noteThickness, 1)
                                gfx.rect(visibleStartX, lowerLineY - yOffsetRect, endX - visibleStartX + 1, noteThickness, 1)

                                -- Calculamos el offset SÓLO para el círculo
                                local yOffsetCircle = noteLineConfig.specialNoteYOffset or 0
                                local finalCircleY = lineY - yOffsetCircle -- Restamos para que positivo sea arriba

                                if startX >= noteLineConfig.hitLineX then
                                    gfx.circle(startX, finalCircleY, circleRadius, 1, 1)
                                elseif endX > noteLineConfig.hitLineX then
                                    gfx.circle(noteLineConfig.hitLineX, finalCircleY, circleRadius, 1, 1)
                                end

                                if i == lastNoteIndex and endX < gfx.w then
                                    gfx.rect(endX - yOffsetRect, upperLineY - yOffsetRect, noteThickness, (lowerLineY - upperLineY) + noteThickness, 1)
                                end
                            else
                                -- Notas normales: Dibujar las dos líneas horizontales con grosor configurable
                                local noteThickness = noteLineConfig.noteThickness or 1
                                local yOffset = math.floor(noteThickness / 2)

                                -- Se añade +1 al ancho para cerrar el gap de 1px con los conectores
                                gfx.rect(visibleStartX, upperLineY - yOffset, endX - visibleStartX + 1, noteThickness, 1)
                                gfx.rect(visibleStartX, lowerLineY - yOffset, endX - visibleStartX + 1, noteThickness, 1)

                                if i == firstNoteIndex and visibleStartX == startX then
                                    gfx.rect(startX - yOffset, upperLineY - yOffset, noteThickness, (lowerLineY - upperLineY) + noteThickness, 1)
                                end
                                if i == lastNoteIndex and endX < gfx.w then
                                    gfx.rect(endX - yOffset, upperLineY - yOffset, noteThickness, (lowerLineY - upperLineY) + noteThickness, 1)
                                end
                            end
                        end
                    end
                    
                    -- Dos lógicas aquí, letras en movimiento y velocidad en pixeles para las notas
                    local speed = (noteLineConfig.vocalScrollSpeedBase or 200) * (noteLineConfig.vocalScrollSpeed or 1.0)
                    local startTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                    local timeDiffStart = startTimeSec - currentTimeSec
                    local startX_unclamped = noteLineConfig.hitLineX + (timeDiffStart * speed)
                    
                    if startX_unclamped < gfx.w then
                        local fade_zone_width = 100.0 
                        local text_x_position = startX_unclamped 
                        local text_y_position = noteLineConfig.yOffset - 18

                        gfx.setfont(1, "SDK_JP_Web 85W", 22) -- Tamaño de la fuente de las letras en movimiento
                        
                        local text_alpha = 1.0
                        if text_x_position < noteLineConfig.hitLineX then
                            local distance_past_hitline = noteLineConfig.hitLineX - text_x_position
                            local fade_progress = distance_past_hitline / fade_zone_width
                            text_alpha = 1.0 - math.max(0, math.min(1.0, fade_progress))
                        end
                        
                        local textToDraw = lyric.text

                        if lyric.originalText:match("^%+") then
                            -- Caso 1:  Si es conectora (+), no mostrar nada
                            textToDraw = ""
                        elseif lyric.endsWithHyphen then
                            -- Caso 2: Es una sílaba que debe continuar (termina en - o =).
                            -- Quitar cualquier guion que "lyric.text" ya pueda tener al final
                            local textWithoutHyphen = textToDraw:gsub("%-$", "")
                            -- Añadir un solo guion limpio al final
                            textToDraw = textWithoutHyphen .. "-"
                        end

                        gfx.r, gfx.g, gfx.b, gfx.a = 1, 1, 1, text_alpha * opacity
                        gfx.x, gfx.y = text_x_position, text_y_position
                        gfx.drawstr(textToDraw)
                    end
                    
                    -- Guardar información de esta nota para la próxima iteración
                    prevLyric = lyric
                    prevEndX = endX
                    prevLineY = lineY
                    prevUpperLineY = upperLineY
                    prevLowerLineY = lowerLineY
                end
            end
            
            -- Reiniciar el prevLyric para la siguiente frase
            prevLyric = nil
            prevEndX = nil
            prevLineY = nil
        end
        
        -- Nueva función para dibujar las líneas conectoras grises para todas las frases visibles
        local function drawAllGreyConnectorLines()
            -- Lógica de velocidad en pixeles para las notas
            local speed = (noteLineConfig.vocalScrollSpeedBase or 200) * (noteLineConfig.vocalScrollSpeed or 1.0)
            
            -- Iterar sobre todas las frases visibles (actual + 4 futuras)
            for phraseIndex = currentPhrase, math.min(currentPhrase + 4, #phrases) do
                local phrase = phrases[phraseIndex]
                if not phrase then
                    break
                end
                
                -- Usar opacidad fija para todas las frases
                local opacity = 0.2
                
                for i = 1, #phrase.lyrics - 1 do
                    local currentLyric = phrase.lyrics[i]
                    local nextLyric = phrase.lyrics[i + 1]
                    
                    if currentLyric.pitch and nextLyric.pitch and 
                       currentLyric.pitch > 0 and nextLyric.pitch > 0 and 
                       currentLyric.pitch ~= HP and nextLyric.pitch ~= HP then
                        
                        local currentLineY
                        if currentLyric.pitch == 26 or currentLyric.pitch == 29 or currentLyric.isToneless then
                            currentLineY = calculatePaddedY(0.5)
                        else
                            currentLineY = getNoteYPosition(currentLyric.pitch, noteLineConfig, calculatePaddedY)
                        end
                        
                        local nextLineY
                        if nextLyric.pitch == 26 or nextLyric.pitch == 29 or nextLyric.isToneless then
                            nextLineY = calculatePaddedY(0.5)
                        else
                            nextLineY = getNoteYPosition(nextLyric.pitch, noteLineConfig, calculatePaddedY)
                        end

                        -- Define los límites y clampea las posiciones Y de las líneas conectoras
                        local topBoundaryY = (noteLineConfig.yOffset - noteLineConfig.areaHeight) + (noteLineConfig.pixelMarginTop or 0)
                        local bottomBoundaryY = noteLineConfig.yOffset - (noteLineConfig.pixelMarginBottom or 0)
                        currentLineY = math.max(topBoundaryY, math.min(bottomBoundaryY, currentLineY))
                        nextLineY = math.max(topBoundaryY, math.min(bottomBoundaryY, nextLineY))
                        
                        -- Lógica de velocidad en pixeles para las notas
                        local currentEndTimeSec = reaper.TimeMap2_beatsToTime(0, currentLyric.endTime)
                        local nextStartTimeSec = reaper.TimeMap2_beatsToTime(0, nextLyric.startTime)
                        local timeDiffEnd = currentEndTimeSec - currentTimeSec
                        local timeDiffStart = nextStartTimeSec - currentTimeSec
                        local currentEndX = noteLineConfig.hitLineX + (timeDiffEnd * speed)
                        local nextStartX = noteLineConfig.hitLineX + (timeDiffStart * speed)
                        
                        -- Determinar si la conexión es visible (al menos una parte debe estar en el HUD)
                        local isVisible = (currentEndX < gfx.w and nextStartX > 20 and currentEndX < nextStartX)
                        
                         if not nextLyric.originalText:match("^%+") then -- No dibujar si hay una línea conectora "+"
                            if isVisible then
                                -- Calcular posiciones "Y" para las líneas superior e inferior
                                local upperCurrentY = currentLineY - noteLineConfig.linesSpacing/2
                                local lowerCurrentY = currentLineY + noteLineConfig.linesSpacing/2
                                local upperNextY = nextLineY - noteLineConfig.linesSpacing/2
                                local lowerNextY = nextLineY + noteLineConfig.linesSpacing/2

                                if noteLineConfig.noteLineStyle == "offset_top" then
                                    upperCurrentY = upperCurrentY + 1
                                    upperNextY = upperNextY + 1
                                elseif noteLineConfig.noteLineStyle == "offset_bottom" then
                                    lowerCurrentY = lowerCurrentY + 1
                                    lowerNextY = lowerNextY + 1
                                end

                                -- Guardar los valores originales de X para los cálculos de interpolación
                                local originalCurrentEndX = currentEndX
                                local originalNextStartX = nextStartX
                                
                                -- Limitar las posiciones "X" para que no se dibujen a la izquierda de la línea de golpeo (x = 150)
                                currentEndX = math.max(noteLineConfig.hitLineX, currentEndX)
                                nextStartX = math.max(noteLineConfig.hitLineX, nextStartX)
                                
                                -- Ajustar también para que no se dibujen fuera del HUD
                                currentEndX = math.min(gfx.w, currentEndX)
                                nextStartX = math.min(gfx.w, nextStartX)
                                
                                -- Si ajustamos currentEndX, interpolar las posiciones Y correspondientes
                                if currentEndX ~= originalCurrentEndX and originalNextStartX ~= originalCurrentEndX then
                                    local mUpper = (upperNextY - upperCurrentY) / (originalNextStartX - originalCurrentEndX)
                                    local mLower = (lowerNextY - lowerCurrentY) / (originalNextStartX - originalCurrentEndX)
                                    upperCurrentY = upperCurrentY + mUpper * (currentEndX - originalCurrentEndX)
                                    lowerCurrentY = lowerCurrentY + mLower * (currentEndX - originalCurrentEndX)
                                end
                                
                                -- Si ajustamos nextStartX, interpolar las posiciones Y correspondientes
                                if nextStartX ~= originalNextStartX and originalNextStartX ~= originalCurrentEndX then
                                    local mUpper = (upperNextY - upperCurrentY) / (originalNextStartX - originalCurrentEndX)
                                    local mLower = (lowerNextY - lowerCurrentY) / (originalNextStartX - originalCurrentEndX)
                                    upperNextY = upperCurrentY + mUpper * (nextStartX - originalCurrentEndX)
                                    lowerNextY = lowerCurrentY + mLower * (nextStartX - originalCurrentEndX)
                                end
                                
                                -- Solo dibujar si las posiciones X son diferentes (evitar líneas verticales)
                                if currentEndX ~= nextStartX and nextStartX >= noteLineConfig.hitLineX then
                                    local thickness = noteLineConfig.noteThickness or 1
                                    local start_y_offset = -math.floor(thickness / 2)
                                    
                                    gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 1.0, 1.0, opacity
                                    
                                    for i = 0, thickness - 1 do
                                        local offset = start_y_offset + i
                                        gfx.line(currentEndX, upperCurrentY + offset, nextStartX, upperNextY + offset, 1)
                                        gfx.line(currentEndX, lowerCurrentY + offset, nextStartX, lowerNextY + offset, 1)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- Función modificada para dibujar las líneas conectoras "+" con iluminación y movimiento correcto del círculo
        local function drawAllPlusConnectorLines()
            -- Lógica de velocidad en pixeles para las notas
            local speed = (noteLineConfig.vocalScrollSpeedBase or 200) * (noteLineConfig.vocalScrollSpeed or 1.0)

            -- Iterar sobre todas las frases visibles (actual + 4 futuras)
            for phraseIndex = currentPhrase, math.min(currentPhrase + 4, #phrases) do
                local phrase = phrases[phraseIndex]
                if not phrase then
                    break
                end
                
                local opacity = 1.0
                local prevLyric = nil
                local prevEndX = nil
                local prevLineY = nil -- Variable indispensable para el inicio de la línea conectora
                
                for i, lyric in ipairs(phrase.lyrics) do
                    if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                        local lineY
                        if lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless then
                            lineY = calculatePaddedY(0.5)
                        else
                            lineY = getNoteYPosition(lyric.pitch, noteLineConfig, calculatePaddedY)
                        end
                        
                        -- Lógica de velocidad en pixeles para las notas
                        local startTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                        local timeDiffStart = startTimeSec - currentTimeSec
                        local startX = noteLineConfig.hitLineX + (timeDiffStart * speed)

                        if lyric.originalText:match("^%+") and prevLyric then
                            -- Lógica de velocidad en pixeles para las notas
                            local prevEndTimeSec = reaper.TimeMap2_beatsToTime(0, prevLyric.endTime)
                            local prevTimeDiffEnd = prevEndTimeSec - currentTimeSec
                            local drawStartX = noteLineConfig.hitLineX + (prevTimeDiffEnd * speed)

                            local drawStartY = prevLineY 
                            local drawEndY = lineY
                            local drawEndX = startX
                            local isVisible = (drawStartX < gfx.w and drawEndX > noteLineConfig.hitLineX and drawStartX < drawEndX)
                            
                            if isVisible then
                                -- Define los límites y clampea las posiciones Y de las líneas conectoras
                                local topBoundaryY = (noteLineConfig.yOffset - noteLineConfig.areaHeight) + (noteLineConfig.pixelMarginTop or 0)
                                local bottomBoundaryY = noteLineConfig.yOffset - (noteLineConfig.pixelMarginBottom or 0)
                                drawStartY = math.max(topBoundaryY, math.min(bottomBoundaryY, drawStartY))
                                drawEndY = math.max(topBoundaryY, math.min(bottomBoundaryY, drawEndY))

                                -- Ajustar los puntos de inicio y fin para que estén dentro del HUD
                                local originalStartX = drawStartX
                                local originalStartY = drawStartY
                                local originalEndX = drawEndX
                                local originalEndY = drawEndY
                                
                                -- Si el inicio está a la izquierda del recogedor, calcular la intersección
                                if drawStartX < noteLineConfig.hitLineX then
                                    if originalEndX ~= originalStartX then
                                        local m = (drawEndY - drawStartY) / (originalEndX - originalStartX)
                                        drawStartY = drawStartY + m * (noteLineConfig.hitLineX - originalStartX)
                                    end
                                    drawStartX = noteLineConfig.hitLineX
                                end
                                
                                -- Calcular las posiciones Y para las líneas superior e inferior, aplicando el estilo de offset
                                local startUpperY = drawStartY - noteLineConfig.linesSpacing/2
                                local startLowerY = drawStartY + noteLineConfig.linesSpacing/2
                                local endUpperY = drawEndY - noteLineConfig.linesSpacing/2
                                local endLowerY = drawEndY + noteLineConfig.linesSpacing/2
                                
                                if noteLineConfig.noteLineStyle == "offset_top" then
                                    startUpperY = startUpperY + 1
                                    endUpperY = endUpperY + 1
                                elseif noteLineConfig.noteLineStyle == "offset_bottom" then
                                    startLowerY = startLowerY + 1
                                    endLowerY = endLowerY + 1
                                end

                                -- Verificar si la línea conectora está activa (basado en el tiempo de la nota conectora)
                                local isConnectorActive = lyric.isActive
                                
                                -- Aplicar color según el estado de la línea conectora
                                if isConnectorActive then
                                    gfx.r = noteLineConfig.hitColor.r; gfx.g = noteLineConfig.hitColor.g; gfx.b = noteLineConfig.hitColor.b; gfx.a = noteLineConfig.hitColor.a * opacity
                                else
                                    gfx.r = noteLineConfig.inactiveColor.r; gfx.g = noteLineConfig.inactiveColor.g; gfx.b = noteLineConfig.inactiveColor.b; gfx.a = noteLineConfig.inactiveColor.a * opacity
                                end
                                
                                local thickness = noteLineConfig.noteThickness or 1
                                local start_y_offset = -math.floor(thickness / 2)

                                for i = 0, thickness - 1 do
                                    local offset = start_y_offset + i
                                    gfx.line(drawStartX, startUpperY + offset, drawEndX, endUpperY + offset, 1)
                                    gfx.line(drawStartX, startLowerY + offset, drawEndX, endLowerY + offset, 1)
                                end
                                
                                -- Detectar si la línea conectora está activa y cruza el recogedor
                                if isConnectorActive and originalStartX < noteLineConfig.hitLineX and originalEndX > noteLineConfig.hitLineX then
                                    if originalEndX ~= originalStartX then
                                        local m = (originalEndY - originalStartY) / (originalEndX - originalStartX)
                                        local hitConnectorY = originalStartY + m * (noteLineConfig.hitLineX - originalStartX)
                                        hitDetected = true
                                        hitY = hitConnectorY
                                    end
                                end
                            end
                        end
                        
                        -- Guardar información de esta nota para la próxima iteración
                        prevLyric = lyric
                        local endTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                        local endTimeDiff = endTimeSec - currentTimeSec
                        prevEndX = noteLineConfig.hitLineX + (endTimeDiff * speed)
                        prevLineY = lineY
                    end
                end
            end
        end
        
        -- Dibujar líneas de notas para varias frases futuras (actual + 4 más)
        drawNoteLines(currentPhraseObj, 1.0)
        
        -- Dibujar las próximas 4 frases con la misma opacidad (1.0)
        for i = 1, 4 do
            local nextPhrase = currentPhrase + i
            if nextPhrase <= #phrases then
                local nextPhraseObj = phrases[nextPhrase]
                drawNoteLines(nextPhraseObj, 1.0)
            end
        end
        
        -- Dibujar todas las líneas conectoras grises
        drawAllGreyConnectorLines()
        
        -- Dibujar todas las líneas conectoras "+"
        drawAllPlusConnectorLines()
        
        -- Dibujar el efecto de golpeo si se detectó
        if hitDetected then
            -- LEER EL NUEVO OFFSET DESDE LA CONFIGURACIÓN
            local yOffset = noteLineConfig.hitCircleYOffset or 0
            
            -- CALCULAR LA POSICIÓN Y FINAL
            -- Restamos el offset para que un valor positivo mueva el círculo hacia arriba
            local finalHitY = hitY - yOffset

            -- Dibujar círculos de efecto en la línea de golpeo (usando la nueva posición Y)
            gfx.r, gfx.g, gfx.b, gfx.a = noteLineConfig.hitColor.r, noteLineConfig.hitColor.g, noteLineConfig.hitColor.b, 0.7
            local outerRadius = noteLineConfig.hitCircleRadius * 1.5
            gfx.circle(noteLineConfig.hitLineX, finalHitY, outerRadius, 0, 1)
            
            -- Dibujar círculo interno (usando la nueva posición Y)
            gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 1.0, 0.3, 1.0
            gfx.circle(noteLineConfig.hitLineX, finalHitY, noteLineConfig.hitCircleRadius, 1, 1)
        end
    end
    
    -- Dibujar título del visualizador
    gfx.r, gfx.g, gfx.b, gfx.a = 1, 1, 1, 1
    gfx.setfont(1, "SDK_JP_Web 85W", 18) -- Genshin Impact font
    local titleText = "Phrase: " .. currentPhrase .. "/" .. #phrases
    local titleW, titleH = gfx.measurestr(titleText)
    
    gfx.x, gfx.y = (gfx.w - titleW) / 2, visualizerY - 25
    gfx.drawstr(titleText)
    
    -- Función para renderizar una frase con los espacios correctos
    local function renderPhrase(phrase, font_size, y_pos, alpha_mult)
        if #phrase.lyrics == 0 then
            gfx.r, gfx.g, gfx.b, gfx.a = 1, 1, 1, alpha_mult or 1
            gfx.setfont(1, "SDK_JP_Web 85W", font_size) -- Genshin Impact font
            local noLyricsText = "[No lyrics found]"
            local textW, _ = gfx.measurestr(noLyricsText)
            gfx.x, gfx.y = (gfx.w - textW) / 2, y_pos
            gfx.drawstr(noLyricsText)
            return
        end
        
        -- Primero, agrupa las letras basándose en conectores
        local word_groups = {}
        local current_group = {}
        
        for i, lyric in ipairs(phrase.lyrics) do
            table.insert(current_group, lyric)
            
            -- Si esta letra no termina con guion, o es la última letra de la frase,
            -- cierra el grupo actual y comienza uno nuevo
            if not lyric.endsWithHyphen or i == #phrase.lyrics then
                table.insert(word_groups, current_group)
                current_group = {}
            end
        end
        
        -- Ahora calcular el ancho total incluyendo espacios entre palabras
        gfx.setfont(1, "SDK_JP_Web 85W", font_size) -- Genshin Impact font
        local spaceWidth = gfx.measurestr(" ")
        local totalWidth = 0
        
        for i, group in ipairs(word_groups) do
            for _, lyric in ipairs(group) do
                local textW, _ = gfx.measurestr(lyric.text)
                totalWidth = totalWidth + textW
            end
            
            -- Añadir espacio después de cada grupo excepto el último
            if i < #word_groups then
                totalWidth = totalWidth + spaceWidth
            end
        end
        
        -- Dibujar los grupos de palabras
        local startX = (gfx.w - totalWidth) / 2
        
        for i, group in ipairs(word_groups) do
            for j, lyric in ipairs(group) do
                local textW, _ = gfx.measurestr(lyric.text)
                
                -- Establecer color basado en el estado, si es sin tono o si tiene Hero Power
                if lyric.hasHeroPower then
                    if lyric.isActive then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorHeroPowerActive.r, textColorHeroPowerActive.g, textColorHeroPowerActive.b, textColorHeroPowerActive.a * (alpha_mult or 1)
                    elseif lyric.hasBeenSung then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorHeroPowerSung.r, textColorHeroPowerSung.g, textColorHeroPowerSung.b, textColorHeroPowerSung.a * (alpha_mult or 1)
                    else
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorHeroPower.r, textColorHeroPower.g, textColorHeroPower.b, textColorHeroPower.a * (alpha_mult or 1)
                    end
                elseif lyric.isToneless then
                    if lyric.isActive then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorTonelessActive.r, textColorTonelessActive.g, textColorTonelessActive.b, textColorTonelessActive.a * (alpha_mult or 1)
                    elseif lyric.hasBeenSung then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorTonelessSung.r, textColorTonelessSung.g, textColorTonelessSung.b, textColorTonelessSung.a * (alpha_mult or 1)
                    else
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorToneless.r, textColorToneless.g, textColorToneless.b, textColorToneless.a * (alpha_mult or 1)
                    end
                else
                    if lyric.isActive then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorActive.r, textColorActive.g, textColorActive.b, textColorActive.a * (alpha_mult or 1)
                    elseif lyric.hasBeenSung then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorSung.r, textColorSung.g, textColorSung.b, textColorSung.a * (alpha_mult or 1)
                    else
                        if alpha_mult and alpha_mult < 1.0 then
                            gfx.r, gfx.g, gfx.b, gfx.a = textColorNextPhrase.r, textColorNextPhrase.g, textColorNextPhrase.b, textColorNextPhrase.a * (alpha_mult or 1)
                        else
                            gfx.r, gfx.g, gfx.b, gfx.a = textColorInactive.r, textColorInactive.g, textColorInactive.b, textColorInactive.a * (alpha_mult or 1)
                        end
                    end
                end
                
                gfx.x, gfx.y = startX, y_pos
                gfx.drawstr(lyric.text)
                startX = startX + textW
            end
            
            -- Añadir espacio después de cada grupo excepto el último
            if i < #word_groups then
                startX = startX + spaceWidth
            end
        end
    end
    
    -- Dibujar la frase actual con tamaño ajustado
    if currentPhraseObj then
        gfx.r, gfx.g, gfx.b, gfx.a = bgColorLyrics.r, bgColorLyrics.g, bgColorLyrics.b, bgColorLyrics.a
        gfx.rect(0, visualizerY, gfx.w, lyricsConfig.phraseHeight, 1)
        renderPhrase(currentPhraseObj, lyricsConfig.fontSize.current, visualizerY + 6)
    end

    -- Dibujar la próxima frase con tamaño ajustado
    if nextPhraseObj then
        gfx.r, gfx.g, gfx.b, gfx.a = bgColorLyrics.r * 0.8, bgColorLyrics.g * 0.8, bgColorLyrics.b * 0.8, bgColorLyrics.a * 0.8
        gfx.rect(0, visualizerY + lyricsConfig.phraseHeight + lyricsConfig.phraseSpacing, 
                 gfx.w, lyricsConfig.phraseHeight, 1)
        renderPhrase(nextPhraseObj, lyricsConfig.fontSize.next, 
                    visualizerY + lyricsConfig.phraseHeight + lyricsConfig.phraseSpacing + 6, 0.9)
    end
end

-- Función para actualizar el estado de las letras y dibujarlas
function updateAndDrawLyrics()
    -- Verificar si hay proyecto activo
    if not isProjectOpen() then
        return
    end
    
    -- Verificar si hay letras válidas
    if #phrases == 0 then
        -- Intentar analizar las letras si aún no se ha hecho
        local success = pcall(function() return parseVocals() end)
        if not success or #phrases == 0 then 
            return 
        end
    end
    
    -- Actualizar el estado activo de las letras
    updateLyricsActiveState(curBeat)
    
    -- Dibujar el visualizador de letras
    drawLyricsVisualizer()
end

-- Mapeo de teclas de acceso rápido
local keyBinds={
    [32]=function() -- Tecla espacio (pausa/reanudar)
        if reaper.GetPlayState()==1 then
            reaper.OnStopButton()
        else
            reaper.OnPlayButton()
        end
    end
}

-- Función principal
function Main()
    local char = gfx.getchar()
    
    -- Detectar si hay un proyecto abierto y si ha cambiado
    local hasProject = isProjectOpen()
    local newProject = hasProject and reaper.EnumProjects(-1) or nil
    
    -- Si el proyecto cambió o no hay proyecto pero había uno antes
    if newProject ~= currentProject then
        currentProject = newProject
        resetState()  -- Reiniciar estado si el proyecto cambió
    end
    
    -- Si no hay proyecto abierto, solo mantener el script activo
    if not hasProject then
        if char ~= -1 then
            reaper.defer(Main)
        end
        return -- No hacer nada más hasta que haya un proyecto
    end
    
    if keyBinds[char] then
        keyBinds[char]()
    end
    
    if reaper.GetPlayState() == 1 then
        curBeat = reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1), reaper.GetPlayPosition())
    else
        curBeat = reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1), reaper.GetCursorPosition())
    end
    
    pcall(updateVocals)
    
    if showLyrics then
        updateAndDrawLyrics()
    end
    
    gfx.set(1.0, 1.0, 1.0, 1.0) -- Blanco
    gfx.x,gfx.y=5,gfx.h-20
    gfx.setfont(1, "SDK_JP_Web 85W", 15) -- Genshin Impact font
    gfx.drawstr(string.format("Version %s",version_num))

    -- RELOJ MONOESPACIADO (GHL)
    -- EL texto "Time"
    local titleString = "Time:"
    local titleW, titleH = gfx.measurestr(titleString)
    gfx.x = (gfx.w - titleW) / 2
    gfx.y = gfx.h - 35
    gfx.drawstr(titleString)

    -- El Valor del Tiempo con espaciado fijo (GHL)
    local totalSeconds = reaper.TimeMap2_beatsToTime(0, curBeat)
    local timeString = string.format("%.3fs", totalSeconds)

    -- Define el ancho fijo para cada carácter del reloj
    -- Valor ajustable por si se cambia el tamaño de la fuente
    local charWidth = 9
    
    -- Calcula el ancho total del bloque de tiempo
    local totalBlockWidth = #timeString * charWidth

    -- Calcula la posición X de inicio para centrar el bloque completo
    local startX = (gfx.w - totalBlockWidth) / 2
    local timeY = gfx.h - 20

    -- Esto dibujar cada carácter del reloj, uno por uno
    for i = 1, #timeString do
        local char = timeString:sub(i, i)
        
        -- Mide el ancho del carácter actual para centrarlo dentro de su espaciado
        local singleCharW, _ = gfx.measurestr(char)

        -- Calcula la posición X del espaciado para este carácter
        local boxX = startX + ((i - 1) * charWidth)

        -- Ajusta la posición X para centrar el carácter dentro de su espaciado
        gfx.x = boxX + (charWidth - singleCharW) / 2
        gfx.y = timeY
        
        gfx.drawstr(char)
    end
    
    gfx.update()

    if char ~= -1 then
        reaper.defer(Main)
    end
end

Main()
