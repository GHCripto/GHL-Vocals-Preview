version_num="1.3"

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

gfx.clear = rgb2num(30, 30, 40) -- color de fondo de la ventana
gfx.init("GHL Vocals Preview", 1000, 300, 0, 480, 150) -- Alto, Ancho, Eje X, Eje Y

-- Configurar conexión con el sintetizador JSFX para el Pitch Guide
reaper.gmem_attach("Effect_PitchGuide")

-- Variables Globales
local char = -1
vocalsTrack = nil
phrases = {}
currentPhrase = 1
local phraseMarkerNote = 105  -- Nota MIDI para el marcador de frases (P1)
local phraseMarkerNoteP2 = 106  -- Marcador de frases alternativo (Rock Band P2 / Harmonías)
local function isPhraseMarker(p) return p == phraseMarkerNote or p == phraseMarkerNoteP2 end
local showLyrics = true       -- Controla si se muestra el visualizador de letras
local showNotesHUD = true     -- Controla si se muestra el visualizador de líneas de notas

-- Colores para las letras
local textColorInactive = {r = 0.15, g = 0.9, b = 0.0, a = 1.0}                          -- Verde
local textColorActive = {r = 0.0, g = 1.0, b = 1.0, a = 1.0}                             -- Azul
local textColorSung = {r = 0.1176471, g = 0.5647059, b = 1.0, a = 1.0}                   -- Azul claro para letras ya cantadas
local bgColorLyrics = {r = 0.1372549, g = 0.1490196, b = 0.2039216, a = 1.0}             -- Fondo para letras

-- Color para la próxima frase (notas con tono)
local textColorNextPhrase = {r = 0.0, g = 1.0, b = 0.5, a = 1.0}                         -- Verde más claro para próxima frase

-- Color para letras sin tono (marcadas con #)
local textColorToneless = {r = 0.55, g = 0.55, b = 0.55, a = 1.0}                        -- Gris para letras sin tono
local textColorTonelessActive = {r = 1.0, g = 1.0, b = 1.0, a = 1.0}                     -- Blanco puro para letras sin tono activas
local textColorTonelessSung = {r = 0.75, g = 0.75, b = 0.75, a = 1.0}                    -- Blanco opaco para letras sin tono ya cantadas

-- Colores en la sección de colores al inicio del script
local textColorHeroPower = {r = 1.0, g = 1.0, b = 0.15, a = 1.0}                         -- Amarillo para letras con Hero Power
local textColorHeroPowerActive = {r = 1.0, g = 0.5, b = 0.3, a = 1.0}                    -- Amarillo brillante para letras Hero Power activas
local textColorHeroPowerSung = {r = 0.9764706, g = 0.8999952, b = 0.5372549, a = 1.0}    -- Amarillo más oscuro para letras Hero Power ya cantadas

-- Variables configurables para ajustar la posición y tamaño del visualizador de letras
local lyricsConfig = {
    height = 110,           -- Altura total del visualizador
    bottomMargin = 30,      -- Margen inferior (negativo = se superpone con el borde)
    phraseHeight = 35,      -- Altura de cada frase (reducida ligeramente)
    phraseSpacing = 1,      -- Espacio entre frases
    bgOpacity = 1.0,        -- Opacidad del fondo (0.0 - 1.0)
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
    
    -- Eliminar el nombre de las pistas
    processedText = processedText:gsub("PART VOCALS", "")
    processedText = processedText:gsub("PRO VOCALS", "")
    
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

-- Configuración para las líneas de notas (márgenes independientes y rewind correcto)
local noteLineConfig = {
    -- COLORES
    backgroundColor          = {r = 0.1176471, g = 0.1176471, b = 0.1568627, a = 0.1},   -- Fondo del área de las líneas de notas
    activeColor              = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},    -- Color de notas activas (FRASES COMPLETAS)
    inactiveColor            = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},    -- Color de notas inactivas (FRASES COMPLETAS)
    sungColor                = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},    -- Color de notas ya cantadas (pasado)
    hitColor                 = {r = 1.0, g = 1.0, b = 0.3, a = 1.0},    -- Color de notas siendo cantadas (presente)
    hitLineColor             = {r = 1.0, g = 1.0, b = 1.0, a = 1.0},    -- Color blanco de la línea vertical de golpe
    hitLineThickness         = 2,                                       -- Grosor en píxeles de la línea
    hitLineFadePct           = 0.45,                                    -- Porcentaje de la altura total para el degradado (0.25 = 25%)
    linesSpacing             = 8,                                       -- Espaciado vertical en pixeles de las líneas de las notas
    specialNoteRadius        = 10,                                      -- Tamaño del círculo de las notas sin tono
    specialNoteYOffset       = 0.5,                                       -- Desplazamiento vertical de notas sin tono. 0 = Default, Positivo = arriba, Negativo = abajo
    noteThickness            = 2,                                       -- Grosor en píxeles de las líneas de las notas y sus conectores
    noteLineStyle            = "default",                               -- Estilo de las líneas. Opciones: "default", "offset_top", "offset_bottom"

    -- RANGO ABSOLUTO DE PITCH
    minPitch                 = 32,                                      -- Nota mínima del "mundo" del HUD
    maxPitch                 = 87,                                      -- Nota máxima del "mundo" del HUD
    
    -- REFERENCIA DE RESOLUCIÓN
    referenceScreenHeight    = 1080,                                    -- Altura de referencia (1080p)

    -- DIMENSIONES DEL HUD
    backgroundHeight         = 0.50,                                    -- Altura del fondo del gameplay (50% de la pantalla)
    yOffset                  = 0,                                       -- Posición vertical (se calcula dinámicamente)
    
    -- LÍNEA DE GOLPE (HITLINE)
    hitLineX                 = 150,                                     -- Posición horizontal de la línea de golpe (px)
    hitLineHeightMultiplier  = 1.5,                                     -- Multiplicador de altura de la HIT LINE en base a "highwayGameplayHeight"
    hitLineFollowsOffset     = false,                                   -- Activar/Desactivar el centrado vertical en base a "verticalCenterOffset"
    hitCircleRadius          = 10,                                      -- tamaño del círculo
    hitCircleYOffset         = 1,                                       -- offset vertical

    -- ALTURA DEL ÁREA JUGABLE
    highwayGameplayHeight    = 0.082,                                   -- Altura total del área de juego (8.2% de la pantalla)
    verticalCenterOffset     = -14.0,                                   -- Desfase vertical del área de juego en pixeles

    -- ZOOM DINÁMICO
    minimumZoomRange         = 18.0,                                    -- Mínimo de semitonos a mostrar
    cameraPadding            = 2.0,                                     -- Padding +/- 2 semitonos
    
    -- VELOCIDAD DE ANIMACIÓN
    panZoomSpeed             = 9.0,                                     -- Suavidad de la cámara
    panZoomBaseSpeed         = 1.0,                                     -- Velocidad base (GHL: 1.0)

    -- BUFFERS DE TIEMPO PARA EL CÁLCULO
    -- Valores directos del binario GHL (FUN_1402ad7a0): lookahead = 4.5 / vocalScrollSpeed, lookbehind = 1.0 / vocalScrollSpeed
    viewFutureSec            = 4.5,                                     -- Constante GHL (se divide por vocalScrollSpeed en runtime)
    viewPastSec              = 1.0,                                     -- Constante GHL (se divide por vocalScrollSpeed en runtime)
    
    -- Estados internos de cámara
    currentMinDisplayPitch   = 52.0, 
    currentMaxDisplayPitch   = 67.0, 
    targetMinDisplayPitch    = 52.0, 
    targetMaxDisplayPitch    = 67.0, 
    
    -- VARIABLE INTERNA PARA CÁLCULO (NO TOCAR)
    _lastTimeSec             = -1000.0,

    vocalScrollSpeed         = 1.1,                                     -- Velocidad del desplazamiento de las notas. Mayor valor, más velocidad
    vocalScrollSpeedBase     = 1920 / 5.5,                              -- Velocidad base de las notas en píxeles por segundo (GHL: 1920 / 5.5 = ~349.09)

    -- PIXEL SNAP POR EJE (GHL)
    ghlPerfectPixelSnapX     = true,                                    -- Eje X: true = pixel perfecto, false = bordes suaves
    ghlPerfectPixelSnapY     = true,                                    -- Eje Y: true = pixel perfecto, false = bordes suaves

    -- PITCH GUIDE (Guía Tonal)
    pitchGuideEnabled        = true,                                    -- Activar el tono de guía (requiere plugin JSFX)
    pitchGuideBufferSeconds  = 5.0,                                     -- Segundos de notas futuras que se envían al sintetizador
    pitchGuideFadeMs         = 0.0,                                     -- Milisegundos de fundido (Fade In/Out) para evitar clicks de audio
    
    -- DEBUG
    showPaddingLines         = false,                                   -- Activar/Desactivar líneas del padding de pixeles (solo números impares)
    paddingLineThickness     = 2,                                       -- Grosor en píxeles (solo números impares)
    paddingLineColor         = {r = 1.0, g = 0.3, b = 0.3, a = 1.0},    -- Rojo semitransparente
    
    staffLineThickness       = 2,                                       -- Grosor en pixeles (2 en GH, 1 por defecto)
    staffLineYOffset         = 0,                                       -- Desplazamiento vertical. 0 = Default, Positivo = arriba, Negativo = abajo
    ghlGuideLineAlpha        = 0.1,                                     -- Opacidad de las líneas guia
}

-- Función para encontrar la pista vocal (prioriza PRO VOCALS sobre PART VOCALS)
function findVocalsTrack()
    -- Primero busca PRO VOCALS
    vocalsTrack = findTrack("PRO VOCALS")
    
    -- Si no existe, busca PART VOCALS como respaldo
    if not vocalsTrack then
        vocalsTrack = findTrack("PART VOCALS")
    end
    if vocalsTrack then
        -- Intentar añadir el FX automáticamente si la guía tonal está activada
        if noteLineConfig.pitchGuideEnabled then
            local fxExists = false
            local fxCount = reaper.TrackFX_GetCount(vocalsTrack)
            
            -- Bucle para leer los nombres de todos los efectos actuales
            for i = 0, fxCount - 1 do
                local _, fxName = reaper.TrackFX_GetFXName(vocalsTrack, i)
                -- Buscamos una coincidencia parcial ignorando prefijos de Reaper y mayúsculas
                if string.find(string.lower(fxName), "pitch guide") or 
                   string.find(string.lower(fxName), "pitch_guide") then
                    fxExists = true
                    break
                end
            end
            
            -- Si el bucle termina y no lo encontró, forzamos la creación (usando 1)
            if not fxExists then
                local fxIndex = reaper.TrackFX_AddByName(vocalsTrack, "Pitch_Guide.jsfx", false, 1)
                if fxIndex < 0 then
                    reaper.TrackFX_AddByName(vocalsTrack, "Pitch Guide", false, 1)
                end
            end
        end
    end
    
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
            
            -- Recolectar todas las notas de Hero Power
            local heroPowerNotes = {}
            for n = 0, noteCount-1 do
                local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
                if pitch == HP then
                    local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
                    local noteEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
                    table.insert(heroPowerNotes, {startTime = noteStartTime, endTime = noteEndTime})
                end
            end
            
            -- Busca los marcadores de frases (105 P1 y 106 P2).
            -- Si una frase tiene ambos marcadores en el mismo tiempo, solo
            -- procesamos uno (descartamos el 106 cuando ya hay 105 coincidente).
            for j = 0, noteCount-1 do
                local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, j)
                local startTime = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
                local endTime = reaper.MIDI_GetProjQNFromPPQPos(take, endppq)

                if isPhraseMarker(pitch) then
                    if pitch == phraseMarkerNoteP2 then
                        local duplicate = false
                        for _, existing in ipairs(phrases) do
                            if math.abs(existing.startTime - startTime) < 0.01 then
                                duplicate = true
                                break
                            end
                        end
                        if not duplicate then
                            table.insert(phrases, createPhrase(startTime, endTime))
                        end
                    else
                        table.insert(phrases, createPhrase(startTime, endTime))
                    end
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
                        
                        -- Si la nota no es un marcador de frase (105 ni 106) y coincide con el tiempo del evento
                        if not isPhraseMarker(pitch) and math.abs(noteStartTime - time) < 0.01 then
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
                    
                    -- Si la nota no es un marcador de frase (105 ni 106) y coincide con el tiempo del evento
                    if not isPhraseMarker(pitch) and math.abs(noteStartTime - event.time) < 0.01 then
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

-- Calcula los límites físicos de la pantalla
local function getHudBounds(ctxHeight)
    local c = noteLineConfig
    
    -- 1. Altura de Notas (0.082) - USANDO REFERENCIA 1080p
    -- Esto asegura que las notas siempre tengan ~88px de alto, aunque la ventana sea de 300px
    local scaleReference = c.referenceScreenHeight or 1080
    local gameplayHeight = scaleReference * (c.highwayGameplayHeight or 0.082)

    -- 2. Altura del Fondo (0.50) - USANDO ALTURA REAL DE VENTANA
    -- El fondo se adapta a tu ventana pequeña
    local hudHeight = ctxHeight * (c.backgroundHeight or 0.50)

    -- 3. Centro
    -- c.yOffset es la parte inferior del visualizador de notas en Lua (encima de letras)
    local hudCenterY = c.yOffset - (hudHeight / 2)
    local effectiveCenterY = hudCenterY + (c.verticalCenterOffset or 0)

    local halfHeight = gameplayHeight * 0.5
    
    return {
        top = effectiveCenterY - halfHeight,
        bottom = effectiveCenterY + halfHeight,
        height = gameplayHeight,
        centerY = effectiveCenterY,
        hudCenterY = hudCenterY, -- Centro del fondo (para hitline sin offset)
        hudHeight = hudHeight,
        hudTop = c.yOffset - hudHeight,
        hudBottom = c.yOffset
    }
end

-- FÓRMULA DE ÍNDICES
-- Convierte nota MIDI a Índice Visual GHL
-- Esto importa para pitches bajos donde los términos de octava son negativos
local function truncToZero(x)
    if x >= 0 then return math.floor(x) else return math.ceil(x) end
end

-- Pixel Snapping
local function snap(x)
    return truncToZero(x + 0.5)
end

-- Snap de posición horizontal (eje X)
local function snapX(x)
    if noteLineConfig.ghlPerfectPixelSnapX then return snap(x) end
    return x
end

-- Snap de posición vertical (eje Y)
local function snapY(x)
    if noteLineConfig.ghlPerfectPixelSnapY then return snap(x) end
    return x
end

local function calculateGHLIndex(pitch)
    local base = pitch
    
    -- Ajuste de Octava 1: truncToZero(val / 12.0 - 3.0)
    local term1 = truncToZero(base / 12.0 - 3.0)
    
    -- Ajuste de Octava 2: truncToZero((val - 5.0) / 12.0 - 2.0)
    local term2 = truncToZero((base - 5.0) / 12.0 - 2.0)
    
    -- Fórmula maestra
    local rawIndex = (base - 40.0 + term1 + term2) * 0.5
    
    return rawIndex
end

-- Función auxiliar: Calcula Y con padding
local function calculatePaddedY(pitchNormalized, bounds)
    -- Invertimos porque Canvas Y crece hacia abajo (bottom es mayor Y)
    return bounds.bottom - (pitchNormalized * bounds.height)
end

-- Z-Path: Calcula los puntos de la curva Z de GHL para una línea del conector
local function getZPathPoints(startX, endX, startY, endY, isUpper, config)
    local dX = endX - startX
    local dY = endY - startY

    if dX <= 0 or math.abs(dY) * 2 < dX then
        return {{x = startX, y = startY}, {x = endX, y = endY}}
    end

    local basicNoteHeight = config.linesSpacing + config.noteThickness
    local curveW = math.min(basicNoteHeight, dX)
    local halfCurve = basicNoteHeight / 2
    local spacingHalf = config.linesSpacing / 2
    local perpInward = (spacingHalf + halfCurve) / 3
    local perpSign = isUpper and 1 or -1
    local curveAtStart = (dY > 0) == isUpper

    if curveAtStart then
        return {
            {x = startX, y = startY},
            {x = startX + curveW * 0.6666667, y = startY + perpInward * perpSign},
            {x = endX, y = endY}
        }
    else
        return {
            {x = startX, y = startY},
            {x = endX - curveW * 0.6666667, y = endY + perpInward * perpSign},
            {x = endX, y = endY}
        }
    end
end

-- Dibuja una línea Z-path en el canvas de REAPER (con grosor y pixel snapping)
local function drawZPath(startX, endX, startY, endY, isUpper, config)
    local points = getZPathPoints(startX, endX, startY, endY, isUpper, config)
    local thickness = config.noteThickness or 1
    local yOff = -math.floor(thickness / 2)

    for seg = 1, #points - 1 do
        local p0 = points[seg]
        local p1 = points[seg + 1]
        for i = 0, thickness - 1 do
            gfx.line(snapX(p0.x), snapY(p0.y) + yOff + i, snapX(p1.x), snapY(p1.y) + yOff + i, 1)
        end
    end
end

-- Verifica si el pitch es válido para calcular límites de cámara
local function isValidPitchForCamera(pitch)
    if not pitch or pitch <= 0 then return false end
    -- GHL ignora notas 26 y 29 para el zoom
    local notPitch29 = (pitch < 28.95 or pitch > 29.05)
    local notPitch26 = (pitch < 25.95 or pitch > 26.05)
    return notPitch29 and notPitch26
end

-- Actualiza los objetivos de la cámara con lógica de Histéresis (Zona Muerta)
local function updateCameraTargets(currentTimeSec, noteList)
    local c = noteLineConfig
    
    -- Ventana de tiempo (Lookahead) - Fórmula GHL: fVar13 = 1.0 / vocalScrollSpeed; fVar16 = fVar13 * 4.5
    -- lookahead efectivo = viewFutureSec / vocalScrollSpeed; lookbehind efectivo = viewPastSec / vocalScrollSpeed
    local invScrollSpeed = 1.0 / c.vocalScrollSpeed
    local startT = currentTimeSec - (c.viewPastSec * invScrollSpeed)
    local endT   = currentTimeSec + (c.viewFutureSec * invScrollSpeed)
    
    local rawMax = -math.huge
    local rawMin = math.huge
    local foundValid = false
    
    -- 1. Calcular rawMin / rawMax basados en notas visibles
    for _, n in ipairs(noteList) do
        if n.time >= startT and n.time <= endT then
            if isValidPitchForCamera(n.pitch) and not n.isToneless then
                rawMin = math.min(rawMin, n.pitch)
                rawMax = math.max(rawMax, n.pitch)
                foundValid = true
            end
        end
    end
    
    if not foundValid then return end
    
    -- 2. Aplicar Padding
    local padding = c.cameraPadding or 2.0
    rawMax = rawMax + padding
    rawMin = rawMin - padding
    
    -- 3. Lógica de Estabilidad (GHL)
    local targetMin = c.targetMinDisplayPitch
    local targetMax = c.targetMaxDisplayPitch
    local currentRange = rawMax - rawMin
    local targetRange = targetMax - targetMin
    local minZoom = c.minimumZoomRange
    
    local shouldUpdate = false
    
    if rawMin < targetMin then
        shouldUpdate = true
    elseif targetMax < rawMax then
        shouldUpdate = true
    elseif minZoom < targetRange and currentRange < targetRange then
        shouldUpdate = true -- "Relax", cerramos la cámara si sobra mucho espacio
    end
    
    -- 4. Actualizar Targets si es necesario
    if shouldUpdate then
        if currentRange < minZoom then
            local expansion = (minZoom - currentRange) * 0.5
            rawMax = rawMax + expansion
            rawMin = rawMin - expansion
        end
        
        -- Clampear a límites absolutos
        if rawMin < c.minPitch then
            rawMin = c.minPitch
            rawMax = math.max(rawMax, rawMin + minZoom)
        end
        if rawMax > c.maxPitch then
            rawMax = c.maxPitch
            rawMin = math.min(rawMin, rawMax - minZoom)
        end
        
        c.targetMinDisplayPitch = rawMin
        c.targetMaxDisplayPitch = rawMax
    end
end

-- Interpola la cámara con movimiento lineal constante (Mecánico)
local function updateDisplayPitchRange(deltaTime)
    local c = noteLineConfig
    local speed = c.panZoomBaseSpeed * c.panZoomSpeed
    
    if deltaTime <= 0 then deltaTime = 1/60 end
    local maxMovement = speed * deltaTime
    
    -- Animar Max Pitch
    local targetMax = c.targetMaxDisplayPitch
    local displayMax = c.currentMaxDisplayPitch
    
    if targetMax > displayMax then
        displayMax = math.min(targetMax, displayMax + maxMovement)
    elseif targetMax < displayMax then
        displayMax = math.max(targetMax, displayMax - maxMovement)
    end
    c.currentMaxDisplayPitch = displayMax
    
    -- Animar Min Pitch
    local targetMin = c.targetMinDisplayPitch
    local displayMin = c.currentMinDisplayPitch
    
    if targetMin > displayMin then
        displayMin = math.min(targetMin, displayMin + maxMovement)
    elseif targetMin < displayMin then
        displayMin = math.max(targetMin, displayMin - maxMovement)
    end
    c.currentMinDisplayPitch = displayMin
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

    -- Cálculo de Posición Y usando Índices GHL
    -- Réplica exacta de NoteRenderer.calculateExactNoteY en JS
    local function getNoteYPosition(pitch, config, bounds)
        local yOffset = config.staffLineYOffset or 0
        
        -- 1. Convertir la nota actual a índice GHL
        local currentIndex = calculateGHLIndex(pitch)
        
        -- 2. Convertir los límites de la cámara a índices GHL (para zoom suave)
        local minIndex = calculateGHLIndex(config.currentMinDisplayPitch)
        local maxIndex = calculateGHLIndex(config.currentMaxDisplayPitch)
        
        -- 3. Normalizar
        local range = maxIndex - minIndex
        local normalized = 0
        if range ~= 0 then
            normalized = (currentIndex - minIndex) / range
        end
        
        -- 4. Clamp a [0, 1] — réplica exacta del JS
        if normalized >= 0.0 then
            if normalized > 1.0 then normalized = 1.0 end
        else
            normalized = 0.0
        end
        
        -- 5. Convertir a píxeles con pixel snap
        local finalY = calculatePaddedY(normalized, bounds) - yOffset
        return snapY(finalY)
    end

    -- Inversa de getNoteYPosition: convierte un píxel Y de la hitline a Pitch (incluyendo conectores)
    local function getPitchFromYPosition(y, bounds)
        local c = noteLineConfig
        local minPaddedY = bounds.top
        local maxPaddedY = bounds.bottom
        
        -- clamp y
        local clampedY = math.max(minPaddedY, math.min(maxPaddedY, y))
        local normalizedPitch = (maxPaddedY - clampedY) / (maxPaddedY - minPaddedY)
        local pitch = (normalizedPitch * (c.currentMaxDisplayPitch - c.currentMinDisplayPitch)) + c.currentMinDisplayPitch
        
        return pitch
    end

    -- Convertidor MIDI a Hz para el sintetizador
    local function midiToFrequency(midiNote)
        return 440.0 * (2.0 ^ ((midiNote - 69.0) / 12.0))
    end

    local currentTimeSec = reaper.TimeMap2_beatsToTime(0, curBeat)
    local deltaTime      = currentTimeSec - (noteLineConfig._lastTimeSec or currentTimeSec)
    noteLineConfig._lastTimeSec = currentTimeSec

    updateCameraTargets(currentTimeSec, phrasesToNotes(phrases))
    updateDisplayPitchRange(deltaTime)

    -- Calcular posición y dimensiones para el visualizador de letras con los nuevos valores
    local visualizerHeight = lyricsConfig.height
    local visualizerY = gfx.h - visualizerHeight - 40 + lyricsConfig.bottomMargin

    -- Posición vertical del HUD
    noteLineConfig.yOffset = visualizerY - 30

    -- Calcular bounds una vez por frame
    local bounds = getHudBounds(gfx.h)

    
    -- Dibujar fondo para el visualizador con opacidad ajustada
    gfx.r, gfx.g, gfx.b, gfx.a = 0.1176471, 0.1176471, 0.1568627, lyricsConfig.bgOpacity
    gfx.rect(0, visualizerY - 30, gfx.w, visualizerHeight + 40, 1)
    
    -- Encontrar la frase actual y la siguiente
    local currentPhraseObj = phrases[currentPhrase]
    local nextPhraseObj = currentPhrase < #phrases and phrases[currentPhrase + 1] or nil
    
    -- Solo dibujar el HUD de notas si está activado
    if showNotesHUD then
        -- Dibujar fondo para las líneas de notas
        local bgCol = noteLineConfig.backgroundColor
        gfx.r, gfx.g, gfx.b, gfx.a = bgCol.r, bgCol.g, bgCol.b, bgCol.a
        gfx.rect(0, bounds.hudTop, gfx.w, bounds.hudHeight, 1)

        -- Dibujar líneas del PADDING
        if noteLineConfig.showPaddingLines then
            local c = noteLineConfig

            -- Establecer el color para las líneas de padding
            gfx.r, gfx.g, gfx.b, gfx.a = c.paddingLineColor.r, c.paddingLineColor.g, c.paddingLineColor.b, c.paddingLineColor.a
            
            -- Calcular la posición Y de la línea SUPERIOR
            local topLineY = bounds.top

            -- Calcular la posición Y de la línea INFERIOR
            local bottomLineY = bounds.bottom
            
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

        -- RENDERIZADO PROCEDIMENTAL DE LÍNEAS STAVE
        local function drawGHLProceduralStave(config, bounds)
            local thickness = config.staffLineThickness or 1
            local rectY_offset = math.floor(thickness / 2)
            
            -- Límites estrictos (Clipping)
            local clipTopY = bounds.top
            local clipBottomY = bounds.bottom
            
            -- Calcular rango actual de cámara en índices GHL
            local minCameraIndex = calculateGHLIndex(config.currentMinDisplayPitch)
            local maxCameraIndex = calculateGHLIndex(config.currentMaxDisplayPitch)
            local range = maxCameraIndex - minCameraIndex
            
            -- Preparar Color
            gfx.r, gfx.g, gfx.b = 1.0, 1.0, 1.0
            gfx.a = config.ghlGuideLineAlpha
            
            -- Iterar índices 0 a 23 (El Hardcap del Binario)
            for i = 0, 23 do
                -- --- REGLAS DEL PORTERO (Hardcoded en ASM) ---
                
                -- Condición compuesta: > 0, != 12, y Pares
                if i > 0 and i ~= 12 and (i % 2) == 0 then
                    
                    -- Calcular posición Y
                    local normalized = 0
                    if range ~= 0 then
                        normalized = (i - minCameraIndex) / range
                    end
                    
                    local lineY = calculatePaddedY(normalized, bounds)
                    
                    -- Clipping Visual
                    if lineY >= clipTopY - 1 and lineY <= clipBottomY + 1 then
                        local rectY = snapY(lineY - rectY_offset)
                        gfx.rect(snapX(0), rectY, gfx.w, thickness, 1)
                    end
                end
            end
            
            gfx.a = 1.0 -- Restaurar alpha
        end

        -- Ejecutar el nuevo dibujado de líneas procedimental
        drawGHLProceduralStave(noteLineConfig, bounds)

        -- Efecto Fade vertical para la línea de golpe
        local c = noteLineConfig
        
        -- Determinar el CENTRO de la línea
        local hitLineCenterY
        if noteLineConfig.hitLineFollowsOffset then
            hitLineCenterY = bounds.centerY -- Seguir al mundo
        else
            hitLineCenterY = bounds.hudCenterY -- Centro del fondo
        end

        local totalHeight = bounds.height * noteLineConfig.hitLineHeightMultiplier
        local halfHeight = totalHeight / 2
        local topY = hitLineCenterY - halfHeight
        local bottomY = hitLineCenterY + halfHeight
        
        -- Asegurarse de que los nuevos parámetros existan para evitar errores
        local thickness = c.hitLineThickness or 3

        -- El tamaño del fade se calcula basado en el porcentaje de la altura total
        local fadeHeight = totalHeight * (c.hitLineFadePct or 0.25)
        local color = c.hitLineColor or {r = 1.0, g = 0.3, b = 0.3, a = 1.0}

        -- Calcular la posición X de inicio para centrar la línea
        local startX = c.hitLineX - math.floor(thickness / 2)

        -- Establecer el color base de la línea
        gfx.r, gfx.g, gfx.b = color.r, color.g, color.b

        -- Iterar verticalmente, píxel por píxel, para dibujar la línea con degradado
        for y = math.floor(topY), math.ceil(bottomY) do
            -- Calcular la distancia al borde más cercano (superior o inferior)
            local distFromTop = y - topY
            local distFromBottom = bottomY - y
            local distToEdge = math.min(distFromTop, distFromBottom)
            
            -- Calcular el alfa basado en la distancia al borde
            local finalAlpha = (distToEdge < fadeHeight and fadeHeight > 0) and (distToEdge / fadeHeight) or 1.0
            
            -- Aplicar el alfa calculado, multiplicado por el alfa base del color
            if finalAlpha > 0.01 then
                gfx.a = color.a * finalAlpha
                -- Dibujar un pequeño rectángulo de 1 píxel de alto para este segmento de la línea
                gfx.rect(startX, y, thickness, 1, 1)
            end
        end
        gfx.a = 1.0 -- Restaurar el alfa para los siguientes dibujos
        
        -- Variable para rastrear si hay alguna nota activa cruzando la línea de golpeo
        local hitDetected = false
        local hitY = 0
        local hitPitch = nil
        
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
                        lineY = calculatePaddedY(0.5, bounds)
                    else
                        lineY = getNoteYPosition(lyric.pitch, noteLineConfig, bounds)
                    end
                    
                    -- Define los límites superior e inferior del área de dibujado de notas
                    -- Esto asegura que lineY nunca se calcule fuera de estos límites para el dibujado
                    lineY = math.max(bounds.top, math.min(bounds.bottom, lineY))
                    
                    -- Lógica de velocidad en pixeles para las notas
                    local speed = (noteLineConfig.vocalScrollSpeedBase or 200) * (noteLineConfig.vocalScrollSpeed or 1.0)
                    local startTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                    local endTimeSec = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                    local timeDiffStart = startTimeSec - currentTimeSec
                    local timeDiffEnd = endTimeSec - currentTimeSec
                    local startX = snapX(noteLineConfig.hitLineX + (timeDiffStart * speed))
                    local endX = snapX(noteLineConfig.hitLineX + (timeDiffEnd * speed))
                    
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
                                
                                local isToneless = (lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless)
                                hitPitch = isToneless and nil or lyric.pitch
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
                        -- Pixel snap en las coordenadas Y de la nota
                        lineY = snapY(lineY)
                        local upperLineY = snapY(lineY - noteLineConfig.linesSpacing/2)
                        local lowerLineY = snapY(lineY + noteLineConfig.linesSpacing/2)
                        
                        if noteLineConfig.noteLineStyle == "offset_top" then
                            upperLineY = upperLineY + 1
                        elseif noteLineConfig.noteLineStyle == "offset_bottom" then
                            lowerLineY = lowerLineY + 1
                        end

                        -- Solo dibujar la parte de las líneas que están a la derecha del recogedor
                        local visibleStartX = math.max(startX, noteLineConfig.hitLineX)
                        
                        -- Solo dibujar si al menos parte de la nota está a la derecha del recogedor
                        if endX > noteLineConfig.hitLineX then

                            -- Notas sin tono con "caras" matemáticas y corrección Y
                            local isSpecialToneless = (lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless)

                            if isSpecialToneless then
                                -- 1. Lógica estricta de 0.125s para colas de notas sin tono.
                                -- startTime/endTime están en BEATS: convertir a segundos antes de comparar.
                                local duration = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                                               - reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                                local isSustained = false
                                if lyric.pitch == 26 then isSustained = true
                                elseif lyric.pitch == 29 then isSustained = false
                                else isSustained = (duration >= 0.125) end

                                local circleRadius = noteLineConfig.specialNoteRadius
                                local noteThickness = noteLineConfig.noteThickness or 1
                                local halfThickness = math.floor((noteThickness / 2) + 0.5)
                                local yOffsetCircle = noteLineConfig.specialNoteYOffset or 0
                                
                                -- 2. Corrección de Y: restamos 0.5 para alinear el círculo al centro matemático exacto entre las dos líneas
                                local finalCircleY = lineY - yOffsetCircle - 0.5 
                                
                                local spacingHalf = noteLineConfig.linesSpacing / 2
                                local safeRatio = math.min(spacingHalf / circleRadius, 0.99)
                                local theta = math.asin(safeRatio)
                                
                                -- 3. Corrección de DX: Usamos circleRadius directo para que la cola inicie exactamente en el borde exterior, no dentro.
                                local dx = circleRadius 

                                local isSingle = (i == firstNoteIndex and i == lastNoteIndex)
                                local isFirst = (i == firstNoteIndex)
                                local isLast = (i == lastNoteIndex)

                                local shape = "MIDDLE"
                                if isSingle then
                                    shape = isSustained and "INITIAL" or "MIDDLE"
                                elseif isFirst then
                                    shape = "INITIAL"
                                elseif isLast then
                                    shape = isSustained and "MIDDLE" or "FINAL"
                                else
                                    shape = "MIDDLE"
                                end

                                -- Dibujar las colas si es sostenida
                                if isSustained and endX > startX then
                                    local lineDrawStart = math.max(visibleStartX, startX + dx)
                                    local lineDrawEnd = endX

                                    if lineDrawEnd > lineDrawStart then
                                        gfx.rect(lineDrawStart, upperLineY - halfThickness, lineDrawEnd - lineDrawStart, noteThickness, 1)
                                        gfx.rect(lineDrawStart, lowerLineY - halfThickness, lineDrawEnd - lineDrawStart, noteThickness, 1)
                                    end

                                    if isLast and endX < gfx.w then
                                        gfx.rect(endX - noteThickness, upperLineY - halfThickness, noteThickness, (lowerLineY - upperLineY) + noteThickness, 1)
                                    end
                                end

                                -- Posición X de la cara (se ancla al hitline si la nota está pasando)
                                local arcX = startX
                                if startX < noteLineConfig.hitLineX and endX > noteLineConfig.hitLineX then
                                    arcX = noteLineConfig.hitLineX
                                end

                                -- Dibujar la cara solo si es visible
                                if endX > noteLineConfig.hitLineX then
                                    -- Si está iluminada (hit o cadena activa), rellenar el interior
                                    if shouldIlluminate then
                                        gfx.circle(arcX, finalCircleY, circleRadius - halfThickness, 1, 1)
                                    end

                                    -- Dibujar los arcos matemáticos para emular las caras de GHL
                                    -- Compensamos sumando math.pi/2 a los ángulos trigonométricos estándar.
                                    local offset = math.pi / 2
                                    for r = circleRadius - halfThickness, circleRadius - halfThickness + noteThickness - 1 do
                                        if shape == "INITIAL" then
                                            gfx.arc(arcX, finalCircleY, r, theta + offset, 2*math.pi - theta + offset, 1)
                                        elseif shape == "FINAL" then
                                            gfx.arc(arcX, finalCircleY, r, math.pi + theta + offset, 3*math.pi - theta + offset, 1)
                                        elseif shape == "MIDDLE" then
                                            gfx.arc(arcX, finalCircleY, r, math.pi + theta + offset, 2*math.pi - theta + offset, 1)
                                            gfx.arc(arcX, finalCircleY, r, theta + offset, math.pi - theta + offset, 1)
                                        else
                                            -- Fallback por si acaso (círculo completo)
                                            gfx.circle(arcX, finalCircleY, r, 0, 1)
                                        end
                                    end
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
                        local text_x_position = snapX(startX_unclamped) 
                        local text_y_position = snapY(noteLineConfig.yOffset - 18)

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
                            currentLineY = calculatePaddedY(0.5, bounds)
                        else
                            currentLineY = getNoteYPosition(currentLyric.pitch, noteLineConfig, bounds)
                        end
                        
                        local nextLineY
                        if nextLyric.pitch == 26 or nextLyric.pitch == 29 or nextLyric.isToneless then
                            nextLineY = calculatePaddedY(0.5, bounds)
                        else
                            nextLineY = getNoteYPosition(nextLyric.pitch, noteLineConfig, bounds)
                        end

                        -- Define los límites y clampea las posiciones Y de las líneas conectoras
                        currentLineY = math.max(bounds.top, math.min(bounds.bottom, currentLineY))
                        nextLineY = math.max(bounds.top, math.min(bounds.bottom, nextLineY))
                        
                        -- Lógica de velocidad en pixeles para las notas
                        local currentEndTimeSec = reaper.TimeMap2_beatsToTime(0, currentLyric.endTime)
                        local nextStartTimeSec = reaper.TimeMap2_beatsToTime(0, nextLyric.startTime)
                        local timeDiffEnd = currentEndTimeSec - currentTimeSec
                        local timeDiffStart = nextStartTimeSec - currentTimeSec
                        local currentEndX = noteLineConfig.hitLineX + (timeDiffEnd * speed)
                        local nextStartX = noteLineConfig.hitLineX + (timeDiffStart * speed)
                        
                        -- Respetar círculo en conectores grises
                        local currentIsToneless = currentLyric.pitch == 26 or currentLyric.pitch == 29 or currentLyric.isToneless
                        local nextIsToneless = nextLyric.pitch == 26 or nextLyric.pitch == 29 or nextLyric.isToneless
                        
                        -- Calculamos el StartX de la nota actual para usarlo como punto de anclaje
                        local cStartTimeSec = reaper.TimeMap2_beatsToTime(0, currentLyric.startTime)
                        local cTimeDiffStart = cStartTimeSec - currentTimeSec
                        local cStartX = noteLineConfig.hitLineX + (cTimeDiffStart * speed)

                        if currentIsToneless then
                            -- startTime/endTime están en BEATS: convertir a segundos antes de comparar.
                            local cDur = reaper.TimeMap2_beatsToTime(0, currentLyric.endTime)
                                       - reaper.TimeMap2_beatsToTime(0, currentLyric.startTime)
                            local cSus = false
                            if currentLyric.pitch == 26 then cSus = true elseif currentLyric.pitch == 29 then cSus = false else cSus = (cDur >= 0.125) end
                            
                            if not cSus then
                                -- Si no es sostenida, el conector gris debe salir desde el borde derecho del círculo
                                currentEndX = cStartX + noteLineConfig.specialNoteRadius - 1
                            else
                                -- Si es sostenida, evitamos que el conector inicie antes del círculo si está muy comprimida
                                currentEndX = math.max(currentEndX, cStartX + noteLineConfig.specialNoteRadius - 1)
                            end
                        end
                        
                        if nextIsToneless then
                            -- El conector gris que llega debe detenerse en el borde izquierdo del siguiente círculo
                            nextStartX = nextStartX - noteLineConfig.specialNoteRadius + 1
                        end

                        -- Determinar si la conexión es visible (al menos una parte debe estar en el HUD)
                        local isVisible = (currentEndX < gfx.w and nextStartX > 20 and currentEndX < nextStartX)
                        
                         if not nextLyric.originalText:match("^%+") then -- No dibujar si hay una línea conectora "+"
                            if isVisible then
                                -- Calcular posiciones "Y" para las líneas superior e inferior
                                local upperCurrentY = snapY(currentLineY - noteLineConfig.linesSpacing/2)
                                local lowerCurrentY = snapY(currentLineY + noteLineConfig.linesSpacing/2)
                                local upperNextY = snapY(nextLineY - noteLineConfig.linesSpacing/2)
                                local lowerNextY = snapY(nextLineY + noteLineConfig.linesSpacing/2)

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
                                    gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 1.0, 1.0, opacity
                                    
                                    -- Z-path GHL para conectores grises
                                    drawZPath(currentEndX, nextStartX, upperCurrentY, upperNextY, true, noteLineConfig)
                                    drawZPath(currentEndX, nextStartX, lowerCurrentY, lowerNextY, false, noteLineConfig)
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
                            lineY = calculatePaddedY(0.5, bounds)
                        else
                            lineY = getNoteYPosition(lyric.pitch, noteLineConfig, bounds)
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
                            
                            -- Respetar círculo en conectores '+'
                            local prevIsToneless = prevLyric.pitch == 26 or prevLyric.pitch == 29 or prevLyric.isToneless
                            
                            if prevIsToneless then
                                -- startTime/endTime están en BEATS: convertir a segundos antes de comparar.
                                local pDur = reaper.TimeMap2_beatsToTime(0, prevLyric.endTime)
                                           - reaper.TimeMap2_beatsToTime(0, prevLyric.startTime)
                                local pSus = false
                                if prevLyric.pitch == 26 then pSus = true elseif prevLyric.pitch == 29 then pSus = false else pSus = (pDur >= 0.125) end
                                
                                local pStartTimeSec = reaper.TimeMap2_beatsToTime(0, prevLyric.startTime)
                                local pTimeDiffStart = pStartTimeSec - currentTimeSec
                                local pStartX = noteLineConfig.hitLineX + (pTimeDiffStart * speed)

                                if not pSus then
                                    drawStartX = pStartX + noteLineConfig.specialNoteRadius - 1
                                else
                                    drawStartX = math.max(drawStartX, pStartX + noteLineConfig.specialNoteRadius - 1)
                                end
                            end
                            
                            local prevLineY
                            if prevLyric.pitch == 26 or prevLyric.pitch == 29 or prevLyric.isToneless then
                                prevLineY = calculatePaddedY(0.5, bounds)
                            else
                                prevLineY = getNoteYPosition(prevLyric.pitch, noteLineConfig, bounds)
                            end

                            local drawStartY = prevLineY 
                            local drawEndY = lineY
                            local drawEndX = startX
                            
                            -- Recortar la llegada del '+' si es toneless
                            local currentIsToneless = lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless
                            if currentIsToneless then
                                drawEndX = drawEndX - noteLineConfig.specialNoteRadius + 1
                            end

                            local isVisible = (drawStartX < gfx.w and drawEndX > noteLineConfig.hitLineX and drawStartX < drawEndX)
                            
                            if isVisible then
                                -- Define los límites y clampea las posiciones Y de las líneas conectoras
                                drawStartY = math.max(bounds.top, math.min(bounds.bottom, drawStartY))
                                drawEndY = math.max(bounds.top, math.min(bounds.bottom, drawEndY))

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
                                
                                -- Z-path GHL para conectores +
                                drawZPath(drawStartX, drawEndX, startUpperY, endUpperY, true, noteLineConfig)
                                drawZPath(drawStartX, drawEndX, startLowerY, endLowerY, false, noteLineConfig)
                                
                                -- Detectar si la línea conectora está activa y cruza el recogedor
                                if isConnectorActive and originalStartX < noteLineConfig.hitLineX and originalEndX > noteLineConfig.hitLineX then
                                    if originalEndX ~= originalStartX then
                                        local m = (originalEndY - originalStartY) / (originalEndX - originalStartX)
                                        local hitConnectorY = originalStartY + m * (noteLineConfig.hitLineX - originalStartX)
                                        hitDetected = true
                                        hitY = hitConnectorY
                                        hitPitch = getPitchFromYPosition(hitConnectorY, bounds)
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

        -- LÓGICA DE AUDIO DEL PITCH GUIDE
        if noteLineConfig.pitchGuideEnabled then
            local playState = reaper.GetPlayState()
            local isPlaying = (playState & 1) == 1
            
            reaper.gmem_write(0, 1) -- Pitch Guide Global Enabled
            reaper.gmem_write(3, isPlaying and 1 or 0) -- Estado de reproducción
            reaper.gmem_write(4, (noteLineConfig.pitchGuideFadeMs or 2.0) / 1000.0) -- Fade in/out en segundos
            
            if isPlaying then
                -- MODO REPRODUCCIÓN: Escribir el buffer del futuro (los próximos 5 segundos)
                local gmem_idx = 20
                local valid_notes_count = 0
                
                for _, ph in ipairs(phrases) do
                    local pStart = reaper.TimeMap2_beatsToTime(0, ph.startTime)
                    local pEnd = reaper.TimeMap2_beatsToTime(0, ph.endTime)
                    
                    -- Escribir las frases que estén reproduciéndose o próximas (basado en la variable pitchGuideBufferSeconds)
                    local bufferSec = noteLineConfig.pitchGuideBufferSeconds or 5.0
                    if currentTimeSec >= pStart - bufferSec and currentTimeSec <= pEnd + bufferSec then
                        for i, lyric in ipairs(ph.lyrics) do
                            if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                                local isToneless = (lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless)
                                if not isToneless then
                                    local lStart = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                                    local lEnd = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                                    
                                    reaper.gmem_write(gmem_idx + 0, lStart)
                                    reaper.gmem_write(gmem_idx + 1, lEnd)
                                    reaper.gmem_write(gmem_idx + 2, midiToFrequency(lyric.pitch))
                                    
                                    -- Un conector es estrictamente un símbolo '+'
                                    local isConnector = string.match(lyric.originalText, "^%+") ~= nil
                                    reaper.gmem_write(gmem_idx + 3, isConnector and 0 or 1) -- 0 = Conector, 1 = Instantánea
                                    
                                    gmem_idx = gmem_idx + 4
                                    valid_notes_count = valid_notes_count + 1
                                end
                            end
                        end
                    end
                end
                
                -- Decirle al JSFX cuántas notas hay en el buffer
                reaper.gmem_write(10, valid_notes_count)
            else
                -- MODO PAUSA/EDICIÓN: Lógica de Clic manual al mover el cursor
                local cursorPos = reaper.GetCursorPosition()
                if noteLineConfig._lastCursorPos ~= cursorPos then
                    noteLineConfig._lastCursorPos = cursorPos
                    noteLineConfig._clickEndTime = reaper.time_precise() + 0.15 -- Click de 150ms
                    
                    -- Buscar qué nota está bajo el cursor para saber qué tono tocar
                    local clickedFreq = 0
                    for _, ph in ipairs(phrases) do
                        local pStart = reaper.TimeMap2_beatsToTime(0, ph.startTime)
                        local pEnd = reaper.TimeMap2_beatsToTime(0, ph.endTime)
                        if cursorPos >= pStart and cursorPos <= pEnd then
                            for _, lyric in ipairs(ph.lyrics) do
                                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                                    local lStart = reaper.TimeMap2_beatsToTime(0, lyric.startTime)
                                    local lEnd = reaper.TimeMap2_beatsToTime(0, lyric.endTime)
                                    local isToneless = (lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless)
                                    if not isToneless and cursorPos >= lStart and cursorPos <= lEnd then
                                        clickedFreq = midiToFrequency(lyric.pitch)
                                        break
                                    end
                                end
                            end
                        end
                        if clickedFreq > 0 then break end
                    end
                    noteLineConfig._lastClickedFreq = clickedFreq
                end
                
                if noteLineConfig._clickEndTime and reaper.time_precise() < noteLineConfig._clickEndTime and (noteLineConfig._lastClickedFreq or 0) > 0 then
                    reaper.gmem_write(1, noteLineConfig._lastClickedFreq)
                else
                    reaper.gmem_write(1, 0) -- Silenciar clic
                    noteLineConfig._clickEndTime = 0
                end
            end
        else
            reaper.gmem_write(0, 0) -- Pitch Guide Global Disabled
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
    
    -- Función auxiliar para dibujar una barra con degradado horizontal (Fade in/out en bordes)
    local function drawCinematicBar(y, height, colorObj, opacityMultiplier)
        local width = gfx.w
        local baseA = (colorObj.a or 1.0) * opacityMultiplier
        
        -- Zonas del degradado (0% a 20%, 20% a 80% sólido, 80% a 100%)
        local fadeZoneWidth = math.floor(width * 0.2)
        local solidZoneStart = fadeZoneWidth
        local solidZoneEnd = width - fadeZoneWidth
        
        gfx.r, gfx.g, gfx.b = colorObj.r, colorObj.g, colorObj.b
        
        -- Dibujar borde izquierdo (Fade In)
        for x = 0, fadeZoneWidth - 1 do
            local progress = x / fadeZoneWidth
            gfx.a = baseA * progress
            gfx.line(x, y, x, y + height - 1)
        end
        
        -- Dibujar zona central (Sólida)
        gfx.a = baseA
        gfx.rect(solidZoneStart, y, solidZoneEnd - solidZoneStart, height, 1)
        
        -- Dibujar borde derecho (Fade Out)
        for x = solidZoneEnd, width - 1 do
            local progress = 1.0 - ((x - solidZoneEnd) / fadeZoneWidth)
            gfx.a = baseA * progress
            gfx.line(x, y, x, y + height - 1)
        end
    end

    -- Función auxiliar para dibujar la línea de acento superior (Efecto cristal)
    local function drawAccentLine(y, width, r, g, b, alpha)
        local fadeZoneWidth = math.floor(width * 0.3)
        local solidZoneStart = fadeZoneWidth
        local solidZoneEnd = width - fadeZoneWidth
        
        gfx.r, gfx.g, gfx.b = r, g, b
        
        -- Borde izquierdo
        for x = 0, fadeZoneWidth - 1 do
            local progress = x / fadeZoneWidth
            gfx.a = alpha * progress
            gfx.rect(x, y, 1, 1, 1)
        end
        
        -- Centro
        gfx.a = alpha
        gfx.rect(solidZoneStart, y, solidZoneEnd - solidZoneStart, 1, 1)
        
        -- Borde derecho
        for x = solidZoneEnd, width - 1 do
            local progress = 1.0 - ((x - solidZoneEnd) / fadeZoneWidth)
            gfx.a = alpha * progress
            gfx.rect(x, y, 1, 1, 1)
        end
    end

    -- Definir color de acento (Cian, basado en 'rgba(68, 255, 253, 0.3)' de tu JS)
    local accentColor = {r = 68/255, g = 255/255, b = 253/255}

    -- Dibujar la frase actual con estilo cinemático
    if currentPhraseObj then
        -- 1. Fondo con gradiente (Opacidad 0.85)
        drawCinematicBar(visualizerY, lyricsConfig.phraseHeight, bgColorLyrics, 0.85)
        
        -- 2. Línea brillante superior (Efecto cristal)
        drawAccentLine(visualizerY, gfx.w, 0.266, 1.0, 0.992, 0.3)
        
        -- Renderizar texto
        renderPhrase(currentPhraseObj, lyricsConfig.fontSize.current, visualizerY + 6, 1.0)
    end

    -- Dibujar la próxima frase con estilo cinemático
    if nextPhraseObj then
        local nextY = visualizerY + lyricsConfig.phraseHeight + lyricsConfig.phraseSpacing
        
        -- Fondo con gradiente más transparente (Opacidad 0.4)
        drawCinematicBar(nextY, lyricsConfig.phraseHeight, bgColorLyrics, 0.4)
        
        -- Renderizar texto (Opacidad 0.6 para jerarquía visual, igual que en tu JS)
        renderPhrase(nextPhraseObj, lyricsConfig.fontSize.next, nextY + 6, 0.6)
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

    -- Esto dibuja cada carácter del reloj, uno por uno
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