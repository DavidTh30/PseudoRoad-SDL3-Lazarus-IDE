program SceneryEditor;

{ Pseudo 3D Road - scenery editor for data\trees.ini, data\bushes.ini and
  data\signs.ini. Every slider and colour changes the live preview at
  once: drive along the real track, or look at the gallery of all scenery
  objects. Save writes the file of the open tab.

  Keys: 1/2/3 tabs, G road/gallery, Space drive/stop, F2 save tab,
        F5 reload all, F6 next season, F7 day/night, Esc quit }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Math, SDL3, p3d_common, p3d_world, p3d_gui;

const
  WinW = 1280;
  WinH = 800;
  PanelX = 10;
  PanelY = 80;
  PanelW = 400;
  PrevX = 420;
  PrevY = 46;
  PrevW = 850;
  PrevH = 638;
  TabNames: array[0..2] of string = ('Trees', 'Bushes', 'Signs');
  TabFiles: array[0..2] of string = ('trees.ini', 'bushes.ini', 'signs.ini');

type
  PRGB = ^TRGB;

  TSceneryDefaults = record
    treeChance, treeOffMin, treeOffMax, pineRatio: Double;
    treeSpMin, treeSpMax: Integer;
    pineTrunk, pineShadow, pineTier, pineLit, pineTop: TRGB;
    treeTrunk, treeBark, treeDark, treeMid, treeLight: TRGB;
    bushChance, bushOffMin, bushOffMax, flowerRatio: Double;
    bushSpMin, bushSpMax: Integer;
    bushDark, bushMid, bushLight, flowerCenter: TRGB;
    flowers: TRGBArray;
    bbFirst, bbSpMin, bbSpMax: Integer;
    bbOffset: Double;
    lampUntil, lampSpacing: Integer;
    lampOffset: Double;
    warnOn: Boolean;
    warnDist: Integer;
    warnOffset: Double;
    chevOn: Boolean;
    chevSpacing: Integer;
    chevMinCurve, chevOffset: Double;
  end;

var
  Win: PSDL_Window = nil;
  PrevTex: PSDL_Texture = nil;
  Tab: Integer = 0;
  Gallery: Boolean = False;
  Driving: Boolean = True;
  DriveSpeed: Double = 0.4;
  CarZ: Double = 0;
  MaxSpeed: Double;
  SelCol: PRGB = nil;
  SelName: string = '';
  Dirty: array[0..2] of Boolean;
  NeedRebuild: Boolean = True;
  NeedShapes: Boolean = False;
  Secs: TTrackSections;
  Def: TSceneryDefaults;
  Clock: Double = 0;
  Status: string = '';
  StatusTime: Double = 0;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 4;
end;

procedure TakeDefaults;
var
  i: Integer;
begin
  Def.treeChance := TreeChance; Def.treeOffMin := TreeOffMin; Def.treeOffMax := TreeOffMax;
  Def.pineRatio := PineRatio; Def.treeSpMin := TreeSpacingMin; Def.treeSpMax := TreeSpacingMax;
  Def.pineTrunk := PineTrunk; Def.pineShadow := PineShadow; Def.pineTier := PineTier;
  Def.pineLit := PineLit; Def.pineTop := PineTop;
  Def.treeTrunk := TreeTrunk; Def.treeBark := TreeBark; Def.treeDark := TreeDark;
  Def.treeMid := TreeMid; Def.treeLight := TreeLight;
  Def.bushChance := BushChance; Def.bushOffMin := BushOffMin; Def.bushOffMax := BushOffMax;
  Def.flowerRatio := FlowerRatio; Def.bushSpMin := BushSpacingMin; Def.bushSpMax := BushSpacingMax;
  Def.bushDark := BushDark; Def.bushMid := BushMid; Def.bushLight := BushLight;
  Def.flowerCenter := FlowerCenter;
  SetLength(Def.flowers, Length(FlowerPalette));
  for i := 0 to High(FlowerPalette) do Def.flowers[i] := FlowerPalette[i];
  Def.bbFirst := BillboardFirst; Def.bbSpMin := BillboardSpacingMin; Def.bbSpMax := BillboardSpacingMax;
  Def.bbOffset := BillboardOffset;
  Def.lampUntil := LampUntil; Def.lampSpacing := LampSpacing; Def.lampOffset := LampOffset;
  Def.warnOn := WarningEnabled; Def.warnDist := WarningDistance; Def.warnOffset := WarningOffset;
  Def.chevOn := ChevronEnabled; Def.chevSpacing := ChevronSpacing;
  Def.chevMinCurve := ChevronMinCurve; Def.chevOffset := ChevronOffset;
end;

procedure RestoreDefaults(which: Integer);
var
  i: Integer;
begin
  case which of
    0: begin
         TreeChance := Def.treeChance; TreeOffMin := Def.treeOffMin; TreeOffMax := Def.treeOffMax;
         PineRatio := Def.pineRatio; TreeSpacingMin := Def.treeSpMin; TreeSpacingMax := Def.treeSpMax;
         PineTrunk := Def.pineTrunk; PineShadow := Def.pineShadow; PineTier := Def.pineTier;
         PineLit := Def.pineLit; PineTop := Def.pineTop;
         TreeTrunk := Def.treeTrunk; TreeBark := Def.treeBark; TreeDark := Def.treeDark;
         TreeMid := Def.treeMid; TreeLight := Def.treeLight;
       end;
    1: begin
         BushChance := Def.bushChance; BushOffMin := Def.bushOffMin; BushOffMax := Def.bushOffMax;
         FlowerRatio := Def.flowerRatio; BushSpacingMin := Def.bushSpMin; BushSpacingMax := Def.bushSpMax;
         BushDark := Def.bushDark; BushMid := Def.bushMid; BushLight := Def.bushLight;
         FlowerCenter := Def.flowerCenter;
         SetLength(FlowerPalette, Length(Def.flowers));
         for i := 0 to High(Def.flowers) do FlowerPalette[i] := Def.flowers[i];
       end;
  else
       begin
         BillboardFirst := Def.bbFirst; BillboardSpacingMin := Def.bbSpMin;
         BillboardSpacingMax := Def.bbSpMax; BillboardOffset := Def.bbOffset;
         LampUntil := Def.lampUntil; LampSpacing := Def.lampSpacing; LampOffset := Def.lampOffset;
         WarningEnabled := Def.warnOn; WarningDistance := Def.warnDist; WarningOffset := Def.warnOffset;
         ChevronEnabled := Def.chevOn; ChevronSpacing := Def.chevSpacing;
         ChevronMinCurve := Def.chevMinCurve; ChevronOffset := Def.chevOffset;
       end;
  end;
  SelCol := nil;
  Dirty[which] := True;
  NeedShapes := True;
  NeedRebuild := True;
end;

{ keep min <= max after a slider moved }
procedure KeepRanges;
begin
  if TreeSpacingMax < TreeSpacingMin then TreeSpacingMax := TreeSpacingMin;
  if TreeOffMax < TreeOffMin then TreeOffMax := TreeOffMin;
  if BushSpacingMax < BushSpacingMin then BushSpacingMax := BushSpacingMin;
  if BushOffMax < BushOffMin then BushOffMax := BushOffMin;
  if BillboardSpacingMax < BillboardSpacingMin then BillboardSpacingMax := BillboardSpacingMin;
end;

procedure SaveTab(which: Integer);
var
  f: string;
begin
  f := DataDir + TabFiles[which];
  try
    case which of
      0: SaveTrees(f);
      1: SaveBushes(f);
    else
      SaveSigns(f);
    end;
    Dirty[which] := False;
    SetStatus('Saved ' + f);
  except
    on E: Exception do SetStatus('Could not save: ' + E.Message);
  end;
end;

procedure ReloadAll;
begin
  LoadAllData(False);
  SelCol := nil;
  Dirty[0] := False; Dirty[1] := False; Dirty[2] := False;
  NeedShapes := True;
  NeedRebuild := True;
  SetStatus('Reloaded trees.ini, bushes.ini and signs.ini');
end;

{ ------------------------------------------------------------- widgets }

procedure Touch(colours: Boolean);
begin
  Dirty[Tab] := True;
  KeepRanges;
  if colours then NeedShapes := True else NeedRebuild := True;
end;

function SliderI(x, y, w: Single; const caption: string; var v: Integer; lo, hi: Integer): Boolean;
var
  d: Double;
begin
  d := v;
  Result := GuiSlider(x, y, w, caption, d, lo, hi, 0);
  if Result then v := Round(d);
end;

procedure Slider(var y: Single; const caption: string; var v: Double; lo, hi: Double; decimals: Integer);
begin
  if GuiSlider(PanelX + 14, y, PanelW - 28, caption, v, lo, hi, decimals) then Touch(False);
  y := y + 36;
end;

procedure SliderInt(var y: Single; const caption: string; var v: Integer; lo, hi: Integer);
begin
  if SliderI(PanelX + 14, y, PanelW - 28, caption, v, lo, hi) then Touch(False);
  y := y + 36;
end;

procedure Toggle(var y: Single; const caption: string; var v: Boolean);
begin
  if GuiButton(PanelX + 14, y, PanelW - 28, 22, caption, v) then
  begin
    v := not v;
    Touch(False);
  end;
  y := y + 30;
end;

procedure Heading(var y: Single; const text: string);
begin
  GuiText(PanelX + 14, y + 4, text, 1.5, 255, 210, 80);
  y := y + 26;
end;

procedure Swatch(x, y: Single; const name: string; var c: TRGB);
begin
  SetCol(c);
  FillR(x, y, 22, 18);
  if SelCol = @c then GuiColor(255, 255, 255) else GuiColor(70, 78, 92);
  GuiFrame(x - 1, y - 1, 24, 20);
  if name <> '' then GuiText(x + 28, y + 5, name);
  if MousePressed and GuiInside(x, y, 180, 18) then
  begin
    SelCol := @c;
    SelName := name;
  end;
end;

procedure ColourEditor(var y: Single);
var
  r, g, b: Double;
  changed: Boolean;
begin
  if SelCol = nil then
  begin
    GuiText(PanelX + 14, y + 4, 'Click a colour to change it.', 1, 170, 175, 190);
    y := y + 22;
    Exit;
  end;
  GuiText(PanelX + 14, y, 'Editing: ' + SelName + '  (' + ColStr(SelCol^) + ')', 1, 255, 220, 120);
  y := y + 16;
  r := SelCol^.r; g := SelCol^.g; b := SelCol^.b;
  changed := GuiSlider(PanelX + 14, y, PanelW - 28, 'Red', r, 0, 255, 0);
  changed := GuiSlider(PanelX + 14, y + 32, PanelW - 28, 'Green', g, 0, 255, 0) or changed;
  changed := GuiSlider(PanelX + 14, y + 64, PanelW - 28, 'Blue', b, 0, 255, 0) or changed;
  if changed then
  begin
    SelCol^ := MakeRGB(Round(r), Round(g), Round(b));
    Touch(True);
  end;
  y := y + 98;
end;

{ ---------------------------------------------------------------- tabs }

procedure TreesTab;
var
  y: Single;
  x2: Single;
begin
  y := PanelY + 10;
  Heading(y, 'Placement');
  Slider(y, 'Chance per row (0-1)', TreeChance, 0, 1, 2);
  SliderInt(y, 'Spacing min (segments)', TreeSpacingMin, 1, 30);
  SliderInt(y, 'Spacing max (segments)', TreeSpacingMax, 1, 30);
  Slider(y, 'Distance min (1 = road edge)', TreeOffMin, 1.2, 12, 2);
  Slider(y, 'Distance max', TreeOffMax, 1.2, 12, 2);
  Slider(y, 'Share of pines (0-1)', PineRatio, 0, 1, 2);
  Heading(y, 'Colours');
  x2 := PanelX + 200;
  Swatch(PanelX + 14, y, 'pine.trunk', PineTrunk);   Swatch(x2, y, 'tree.trunk', TreeTrunk);
  y := y + 24;
  Swatch(PanelX + 14, y, 'pine.shadow', PineShadow); Swatch(x2, y, 'tree.bark', TreeBark);
  y := y + 24;
  Swatch(PanelX + 14, y, 'pine.tier', PineTier);     Swatch(x2, y, 'tree.dark', TreeDark);
  y := y + 24;
  Swatch(PanelX + 14, y, 'pine.lit', PineLit);       Swatch(x2, y, 'tree.mid', TreeMid);
  y := y + 24;
  Swatch(PanelX + 14, y, 'pine.top', PineTop);       Swatch(x2, y, 'tree.light', TreeLight);
  y := y + 30;
  ColourEditor(y);
end;

procedure BushesTab;
var
  y, x: Single;
  i, n: Integer;
begin
  y := PanelY + 10;
  Heading(y, 'Placement');
  Slider(y, 'Chance per step (0-1)', BushChance, 0, 1, 2);
  SliderInt(y, 'Spacing min (segments)', BushSpacingMin, 1, 20);
  SliderInt(y, 'Spacing max (segments)', BushSpacingMax, 1, 20);
  Slider(y, 'Distance min (1 = road edge)', BushOffMin, 1.0, 8, 2);
  Slider(y, 'Distance max', BushOffMax, 1.0, 8, 2);
  Slider(y, 'Share with flowers (0-1)', FlowerRatio, 0, 1, 2);
  Heading(y, 'Colours');
  Swatch(PanelX + 14, y, 'bush.dark', BushDark);
  Swatch(PanelX + 200, y, 'bush.mid', BushMid);
  y := y + 24;
  Swatch(PanelX + 14, y, 'bush.light', BushLight);
  Swatch(PanelX + 200, y, 'flower centre', FlowerCenter);
  y := y + 28;
  GuiText(PanelX + 14, y + 4, 'Flowers');
  x := PanelX + 80;
  n := Length(FlowerPalette);
  for i := 0 to n - 1 do
  begin
    Swatch(x, y, '', FlowerPalette[i]);
    if SelCol = @FlowerPalette[i] then SelName := 'flower ' + IntToStr(i + 1);
    x := x + 28;
  end;
  if GuiButton(x + 4, y - 1, 24, 20, '+') and (n < 8) then
  begin
    SelCol := nil;
    SetLength(FlowerPalette, n + 1);
    if n > 0 then FlowerPalette[n] := FlowerPalette[n - 1]
    else FlowerPalette[n] := MakeRGB(240, 120, 170);
    SelCol := @FlowerPalette[n];
    SelName := 'flower ' + IntToStr(n + 1);
    Touch(False);
  end;
  if GuiButton(x + 32, y - 1, 24, 20, '-') and (n > 1) then
  begin
    SelCol := nil;
    SetLength(FlowerPalette, n - 1);
    Touch(False);
  end;
  y := y + 30;
  ColourEditor(y);
end;

procedure SignsTab;
var
  y: Single;
begin
  y := PanelY + 10;
  Heading(y, 'Billboards');
  SliderInt(y, 'First at segment', BillboardFirst, 0, 400);
  SliderInt(y, 'Spacing min', BillboardSpacingMin, 10, 600);
  SliderInt(y, 'Spacing max', BillboardSpacingMax, 10, 600);
  Slider(y, 'Distance (1 = road edge)', BillboardOffset, 1.1, 4, 2);
  Heading(y, 'Street lamps');
  SliderInt(y, 'Until segment', LampUntil, 0, 2000);
  SliderInt(y, 'Spacing', LampSpacing, 2, 60);
  Slider(y, 'Distance', LampOffset, 1.0, 3, 2);
  Heading(y, 'Bend warning sign');
  Toggle(y, 'Warning signs on', WarningEnabled);
  SliderInt(y, 'Segments before the bend', WarningDistance, 0, 100);
  Heading(y, 'Chevrons');
  Toggle(y, 'Chevrons on', ChevronEnabled);
  SliderInt(y, 'Spacing', ChevronSpacing, 2, 40);
  Slider(y, 'Only bends sharper than', ChevronMinCurve, 0.5, 8, 1);
end;

{ ------------------------------------------------------------ preview }

procedure DrawGallery;
const
  Kinds: array[0..7] of TSpriteKind = (skPine, skTree, skBush, skFlowerBush, skBillboard,
                                       skPole, skChevron, skWarning);
  Names: array[0..7] of string = ('pine', 'tree', 'bush', 'flowers', 'billboard', 'lamp',
                                  'chevron', 'warning');
var
  i, y: Integer;
  total, u, x, w, baseY: Double;
  sp: TSprite;
begin
  baseY := 560;
  y := 0;
  while y < ScreenH do
  begin
    if y < baseY then SetCol(Mix(ColSkyTop, ColSkyBottom, y / baseY))
    else SetCol(Mix(ColGrassL, ColGrassD, (y - baseY) / (ScreenH - baseY)));
    FillR(0, y, ScreenW, 4);
    Inc(y, 4);
  end;
  total := 0;
  for i := 0 to 7 do total := total + SpriteWidth(Kinds[i]);
  u := (ScreenW - 20 - 7 * 10) / total;
  x := 10;
  for i := 0 to 7 do
  begin
    w := SpriteWidth(Kinds[i]) * u;
    sp.kind := Kinds[i];
    sp.offset := -2;
    sp.variant := 1;
    if Kinds[i] = skBillboard then sp.variant := Trunc(Clock / 1.5) mod Max(1, Shapes[skBillboard].variants);
    if Kinds[i] = skFlowerBush then sp.variant := Trunc(Clock / 1.5) mod Max(1, Length(FlowerPalette));
    DrawSprite(sp, x + w / 2, baseY, u, ScreenH, 1);
    DrawText((x + w / 2 - Length(Names[i]) * 6) / 1.5, (baseY + 16) / 1.5, Names[i], 1.5);
    x := x + w + 10;
  end;
  DrawText(10, 10, 'Gallery - billboards and flowers change every 1.5 s', 1.5);
end;

procedure DrawPreview;
var
  dst: TSDL_FRect;
  y: Single;
  i: Integer;
begin
  if PrevTex <> nil then
  begin
    SDL_SetRenderTarget(Ren, PrevTex);
    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    if Gallery then DrawGallery
    else RenderWorld(Cam, CarZ, 0, True, PlayerColor, 0, 0);
    SDL_SetRenderTarget(Ren, nil);
    dst.x := PrevX; dst.y := PrevY; dst.w := PrevW; dst.h := PrevH;
    SDL_RenderTexture(Ren, PrevTex, nil, @dst);
  end;
  GuiColor(70, 78, 92);
  GuiFrame(PrevX, PrevY, PrevW, PrevH);
  if not Gallery then
    DrawMinimap(PrevX + PrevW - 150, PrevY + 8, 142, CarZ, False, -1, -1);

  y := PrevY + PrevH + 10;
  if GuiButton(PrevX, y, 130, 26, 'Road view', not Gallery) then Gallery := False;
  if GuiButton(PrevX + 136, y, 130, 26, 'Gallery (G)', Gallery) then Gallery := True;
  if GuiButton(PrevX + 290, y, 130, 26, 'Drive (Space)', Driving) then Driving := not Driving;
  GuiSlider(PrevX + 440, y - 2, 200, 'Speed', DriveSpeed, 0, 1, 2);

  // season and time of day of the preview (the game's choice is not changed)
  y := y + 34;
  GuiText(PrevX, y + 7, 'Look:', 1, 170, 175, 190);
  for i := 0 to 3 do
    if GuiButton(PrevX + 50 + i * 96, y, 90, 24, SeasonTitles[i], SeasonIdx = i) then
      SetLook(i, NightMode);
  if GuiButton(PrevX + 440, y, 80, 24, 'Day', not NightMode) then SetLook(SeasonIdx, False);
  if GuiButton(PrevX + 526, y, 80, 24, 'Night', NightMode) then SetLook(SeasonIdx, True);
  if GuiButton(PrevX + 612, y, 100, 24, 'Weather', ShowWeather) then ShowWeather := not ShowWeather;
end;

procedure DrawUI;
var
  i: Integer;
  cap: string;
begin
  GuiColor(16, 18, 24);
  GuiFill(0, 0, WinW, WinH);
  GuiText(10, 14, 'SCENERY EDITOR', 2, 255, 210, 80);
  GuiText(260, 20, DataDir + TabFiles[Tab]);

  for i := 0 to 2 do
  begin
    cap := IntToStr(i + 1) + ' ' + TabNames[i];
    if Dirty[i] then cap := cap + ' *';
    if GuiButton(PanelX + i * 134, 46, 128, 28, cap, Tab = i) then
    begin
      Tab := i;
      SelCol := nil;
    end;
  end;

  GuiPanel(PanelX, PanelY, PanelW, 640, '');
  case Tab of
    0: TreesTab;
    1: BushesTab;
  else
    SignsTab;
  end;

  DrawPreview;

  if GuiButton(PanelX, WinH - 70, 128, 28, 'Save tab (F2)') then SaveTab(Tab);
  if GuiButton(PanelX + 134, WinH - 70, 128, 28, 'Save all') then
  begin
    SaveTab(0); SaveTab(1); SaveTab(2);
    SetStatus('Saved trees.ini, bushes.ini and signs.ini');
  end;
  if GuiButton(PanelX + 268, WinH - 70, 132, 28, 'Reload all (F5)') then ReloadAll;
  if GuiButton(PanelX, WinH - 36, 400, 26, 'Built-in defaults for this tab') then
  begin
    RestoreDefaults(Tab);
    SetStatus('Built-in ' + TabNames[Tab] + ' settings (not saved yet)');
  end;
  if StatusTime > 0 then GuiText(PrevX + 660, PrevY + PrevH + 18, Status, 1, 255, 220, 120);
end;

{ ---------------------------------------------------------------- main }

var
  Ev: TSDL_Event;
  Running: Boolean;
  Freq, LastTick, NowTick: UInt64;
  FrameTime, travelled, curve: Double;
  sc: TSDL_Scancode;
  renderer: PSDL_Renderer;
  i: Integer;

begin
  Randomize;
  InitCommon;
  InitWorld;
  SetDefaultData;
  TakeDefaults;
  LoadAllData(True);
  MaxSpeed := SegLen / StepTime;
  Secs := LoadTrackSections(DataDir + 'track.txt');

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  renderer := nil;
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Scenery editor', WinW, WinH, 0, @Win, @renderer) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  Ren := renderer;
  GuiRen := renderer;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  PrevTex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, ScreenW, ScreenH);

  ReloadWorldGraphics;
  BuildTrack(Secs, 777);
  ResetTraffic(MaxSpeed);

  Freq := SDL_GetPerformanceFrequency;
  LastTick := SDL_GetPerformanceCounter;
  Running := True;
  while Running do
  begin
    GuiBeginFrame;
    while SDL_PollEvent(@Ev) do
    begin
      GuiEvent(Ev);
      if Ev._type = SDL_EVENT_QUIT then Running := False
      else if Ev._type = SDL_EVENT_KEY_DOWN then
      begin
        sc := Ev.key.scancode;
        if sc = SDL_SCANCODE_ESCAPE then Running := False
        else if sc = SDL_SCANCODE_1 then begin Tab := 0; SelCol := nil; end
        else if sc = SDL_SCANCODE_2 then begin Tab := 1; SelCol := nil; end
        else if sc = SDL_SCANCODE_3 then begin Tab := 2; SelCol := nil; end
        else if sc = SDL_SCANCODE_G then Gallery := not Gallery
        else if sc = SDL_SCANCODE_SPACE then Driving := not Driving
        else if sc = SDL_SCANCODE_F2 then SaveTab(Tab)
        else if sc = SDL_SCANCODE_F5 then ReloadAll
        else if sc = SDL_SCANCODE_F6 then SetLook((SeasonIdx + 1) mod 4, NightMode)
        else if sc = SDL_SCANCODE_F7 then SetLook(SeasonIdx, not NightMode);
      end;
    end;

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;
    Clock := Clock + FrameTime;

    // apply edits to the preview
    if NeedShapes then
    begin
      RebuildNamedColors;
      LoadShapes;
      NeedShapes := False;
    end;
    if NeedRebuild then
    begin
      BuildTrack(Secs, 777);
      if CarZ >= TrackLength then CarZ := 0;
      NeedRebuild := False;
    end;

    if Driving and (TrackLength > 0) then
    begin
      travelled := DriveSpeed * MaxSpeed * FrameTime;
      curve := Segments[FindSegment(CarZ + PlayerZ)].curve;
      CarZ := Increase(CarZ, travelled, TrackLength);
      SkyOffset := WrapUnit(SkyOffset + 0.001 * curve * travelled / SegLen);
      HillOffset := WrapUnit(HillOffset + 0.002 * curve * travelled / SegLen);
    end;
    for i := 0 to High(Cars) do
      Cars[i].z := Increase(Cars[i].z, Cars[i].speed * FrameTime, TrackLength);

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    DrawUI;
    SDL_RenderPresent(Ren);
  end;

  FreeTextures;
  if PrevTex <> nil then SDL_DestroyTexture(PrevTex);
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
