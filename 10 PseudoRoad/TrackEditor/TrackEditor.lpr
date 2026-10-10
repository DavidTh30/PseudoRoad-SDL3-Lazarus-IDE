program TrackEditor;

{ Pseudo 3D Road - track (map) editor.
  Opens data\track.txt as a list of road sections. Select a section to
  change its type and numbers; add, duplicate, delete or move sections.
  The map, the height profile and a 3D fly-through preview update at once.
  Save writes data\track.txt.

  Keys: Up/Down select, Space play/pause preview, J jump to section,
        Shift = bigger steps, F2 save, F5 reload, Esc quit }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Math, SDL3, p3d_common, p3d_world, p3d_gui;

const
  WinW = 1280;
  WinH = 800;
  ListX = 20;
  ListY = 86;
  ListW = 400;
  RowH = 20;
  ListRows = 19;
  MapX0 = 440;
  MapY0 = 50;
  MapS = 380;
  PrevX = 836;
  PrevY = 50;
  PrevW = 428;
  PrevH = 321;
  ProfX = 440;
  ProfY = 470;
  ProfW = 824;
  ProfH = 170;

var
  Win: PSDL_Window = nil;
  PreviewTex: PSDL_Texture = nil;
  Secs: TTrackSections;
  Sel: Integer = 0;
  ListTop: Integer = 0;
  PreviewZ: Double = 0;
  Playing: Boolean = True;
  PlaySpeed: Double = 0.5;
  MaxSpeed: Double;
  OwnTrack: Boolean = True;
  Status: string = '';
  StatusTime: Double = 0;
  Dirty: Boolean = False;
  ProfMin, ProfMax: Double;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 4;
end;

procedure Rebuild;
var
  i: Integer;
begin
  OwnTrack := BuildTrack(Secs, 4242);
  ResetTraffic(MaxSpeed);
  if PreviewZ >= TrackLength then PreviewZ := 0;
  ProfMin := 0; ProfMax := 0;
  for i := 0 to High(Segments) do
  begin
    ProfMin := MinD(ProfMin, Segments[i].p1.wy);
    ProfMax := MaxD(ProfMax, Segments[i].p1.wy);
  end;
  if ProfMax - ProfMin < 1000 then ProfMax := ProfMin + 1000;
end;

function SectionFirst(i: Integer): Integer;
begin
  if (i >= 0) and (i < Length(SectionStarts)) and OwnTrack then Result := SectionStarts[i]
  else Result := 0;
end;

function SectionLast(i: Integer): Integer;
begin
  if not OwnTrack then Exit(-1);
  if i + 1 < Length(SectionStarts) then Result := SectionStarts[i + 1] - 1
  else Result := Length(Segments) - 1;
end;

procedure JumpToSection;
begin
  PreviewZ := SectionFirst(Sel) * SegLen;
end;

procedure DoSave;
begin
  try
    SaveTrackSections(DataDir + 'track.txt', Secs);
    Dirty := False;
    SetStatus('Saved data\track.txt');
  except
    on E: Exception do SetStatus('Could not save: ' + E.Message);
  end;
end;

procedure DoReload;
begin
  Secs := LoadTrackSections(DataDir + 'track.txt');
  if Length(Secs) = 0 then Secs := DefaultTrackSections;
  Sel := 0;
  ListTop := 0;
  Rebuild;
  Dirty := False;
  SetStatus('Reloaded data\track.txt');
end;

procedure InsertSection(at: Integer; const s: TTrackSection);
var
  i: Integer;
begin
  SetLength(Secs, Length(Secs) + 1);
  for i := High(Secs) downto at + 1 do Secs[i] := Secs[i - 1];
  Secs[at] := s;
end;

procedure DeleteSection(at: Integer);
var
  i: Integer;
begin
  if (at < 0) or (at > High(Secs)) then Exit;
  for i := at to High(Secs) - 1 do Secs[i] := Secs[i + 1];
  SetLength(Secs, Length(Secs) - 1);
end;

procedure SwapSections(a, b: Integer);
var
  t: TTrackSection;
begin
  if (a < 0) or (b < 0) or (a > High(Secs)) or (b > High(Secs)) then Exit;
  t := Secs[a];
  Secs[a] := Secs[b];
  Secs[b] := t;
end;

procedure Changed;
begin
  Dirty := True;
  Rebuild;
end;

procedure KeepSelVisible;
begin
  if Sel < ListTop then ListTop := Sel;
  if Sel >= ListTop + ListRows then ListTop := Sel - ListRows + 1;
  ListTop := EnsureRange(ListTop, 0, Max(0, Length(Secs) - ListRows));
end;

function ParamStep(const name: string): Double;
begin
  if name = 'curve' then
  begin
    if ShiftDown then Result := 2 else Result := 0.5;
  end
  else if name = 'height' then
  begin
    if ShiftDown then Result := 20 else Result := 5;
  end
  else
  begin
    if ShiftDown then Result := 25 else Result := 5;
  end;
end;

procedure ClampParam(var s: TTrackSection; i: Integer);
var
  name: string;
begin
  name := SectionParamNames[s.kind, i];
  if name = 'curve' then s.p[i] := ClampD(s.p[i], -12, 12)
  else if name = 'height' then s.p[i] := ClampD(s.p[i], -300, 300)
  else if (name = 'length') or (name = 'enter') or (name = 'hold') or (name = 'leave') then
    s.p[i] := ClampD(s.p[i], 0, 1000);
end;

procedure DrawList;
var
  i, r: Integer;
  y: Single;
  txt: string;
begin
  GuiText(ListX, ListY - 18, Format('Sections (%d)', [Length(Secs)]), 1, 255, 210, 80);
  GuiColor(26, 30, 38);
  GuiFill(ListX, ListY, ListW, ListRows * RowH);
  if GuiInside(ListX, ListY, ListW, ListRows * RowH) and (WheelY <> 0) then
    ListTop := EnsureRange(ListTop - Round(WheelY) * 3, 0, Max(0, Length(Secs) - ListRows));
  for r := 0 to ListRows - 1 do
  begin
    i := ListTop + r;
    if i > High(Secs) then Break;
    y := ListY + r * RowH;
    if i = Sel then
    begin
      GuiColor(200, 150, 30, 160);
      GuiFill(ListX, y, ListW, RowH);
    end
    else if GuiInside(ListX, y, ListW, RowH) then
    begin
      GuiColor(255, 255, 255, 25);
      GuiFill(ListX, y, ListW, RowH);
    end;
    txt := Format('%3d  %s', [i + 1, SectionToLine(Secs[i])]);
    GuiText(ListX + 8, y + 6, txt);
    if MousePressed and GuiInside(ListX, y, ListW, RowH) then
    begin
      Sel := i;
      if not Playing then JumpToSection;
    end;
  end;
  GuiColor(70, 78, 92);
  GuiFrame(ListX, ListY, ListW, ListRows * RowH);
end;

procedure DrawSectionEditor;
var
  y: Single;
  d, i: Integer;
  k: TSectionKind;
  s: TTrackSection;
  bw: Single;
begin
  y := ListY + ListRows * RowH + 10;
  bw := 76;
  if GuiButton(ListX, y, bw, 24, 'Add after') then
  begin
    if Length(Secs) = 0 then InsertSection(0, DefaultSection(tkStraight))
    else
    begin
      InsertSection(Sel + 1, DefaultSection(tkStraight));
      Inc(Sel);
    end;
    KeepSelVisible;
    Changed;
  end;
  if GuiButton(ListX + 81, y, bw, 24, 'Duplicate') and (Length(Secs) > 0) then
  begin
    InsertSection(Sel + 1, Secs[Sel]);
    Inc(Sel);
    KeepSelVisible;
    Changed;
  end;
  if GuiButton(ListX + 162, y, bw, 24, 'Delete') and (Length(Secs) > 0) then
  begin
    DeleteSection(Sel);
    Sel := EnsureRange(Sel, 0, Max(0, High(Secs)));
    KeepSelVisible;
    Changed;
  end;
  if GuiButton(ListX + 243, y, bw, 24, 'Move up') and (Sel > 0) then
  begin
    SwapSections(Sel, Sel - 1);
    Dec(Sel);
    KeepSelVisible;
    Changed;
  end;
  if GuiButton(ListX + 324, y, bw, 24, 'Move down') and (Sel < High(Secs)) then
  begin
    SwapSections(Sel, Sel + 1);
    Inc(Sel);
    KeepSelVisible;
    Changed;
  end;

  y := y + 40;
  GuiPanel(ListX, y, ListW, 196, '');
  if Length(Secs) = 0 then
  begin
    GuiText(ListX + 12, y + 14, 'No sections - press "Add after"', 1, 255, 220, 120);
    Exit;
  end;
  s := Secs[Sel];
  GuiText(ListX + 12, y + 10, Format('Section %d', [Sel + 1]), 1.5, 255, 210, 80);
  y := y + 34;
  d := GuiSpin(ListX + 12, y, ListW - 24, 'Type', SectionNames[s.kind]);
  if d <> 0 then
  begin
    k := TSectionKind((Ord(s.kind) + Ord(High(TSectionKind)) + 1 + d) mod (Ord(High(TSectionKind)) + 1));
    s := DefaultSection(k);
    Secs[Sel] := s;
    Changed;
  end;
  y := y + 28;
  for i := 0 to SectionParamCount[s.kind] - 1 do
  begin
    d := GuiSpin(ListX + 12, y, ListW - 24, SectionParamNames[s.kind, i], NumStr(s.p[i]));
    if d <> 0 then
    begin
      s.p[i] := s.p[i] + d * ParamStep(SectionParamNames[s.kind, i]);
      ClampParam(s, i);
      Secs[Sel] := s;
      Changed;
    end;
    y := y + 26;
  end;
  if SectionParamCount[s.kind] = 0 then
    GuiText(ListX + 12, y + 4, 'This section has a fixed shape.', 1, 170, 175, 190);
end;

procedure DrawProfile;
var
  i, n, x, a, b: Integer;
  h, y0, y1, px: Single;
begin
  GuiText(ProfX, ProfY - 16, 'Height profile (whole lap, selected section in yellow)', 1, 255, 210, 80);
  GuiColor(22, 26, 34);
  GuiFill(ProfX, ProfY, ProfW, ProfH);
  n := Length(Segments);
  if n = 0 then Exit;
  a := SectionFirst(Sel);
  b := SectionLast(Sel);
  // zero line
  y0 := ProfY + ProfH - 10 - (0 - ProfMin) / (ProfMax - ProfMin) * (ProfH - 20);
  GuiColor(60, 66, 80);
  GuiFill(ProfX, y0, ProfW, 1);
  for x := 0 to ProfW - 1 do
  begin
    i := Min(n - 1, Trunc(x / ProfW * n));
    h := Segments[i].p1.wy;
    y1 := ProfY + ProfH - 10 - (h - ProfMin) / (ProfMax - ProfMin) * (ProfH - 20);
    if (i >= a) and (i <= b) then GuiColor(255, 190, 40) else GuiColor(90, 170, 110);
    GuiFill(ProfX + x, y1, 1, ProfY + ProfH - y1);
  end;
  px := ProfX + FindSegment(PreviewZ) / n * ProfW;
  GuiColor(255, 255, 255);
  GuiFill(px, ProfY, 2, ProfH);
  GuiColor(70, 78, 92);
  GuiFrame(ProfX, ProfY, ProfW, ProfH);
  if MouseDown and GuiInside(ProfX, ProfY, ProfW, ProfH) then
    PreviewZ := Trunc((MouseX - ProfX) / ProfW * n) * SegLen;
end;

procedure DrawInfo;
var
  y: Single;
  endH: Double;
begin
  y := ProfY + ProfH + 14;
  endH := 0;
  if Length(Segments) > 0 then endH := Segments[High(Segments)].p2.wy / SegLen;
  // top speed (SegLen / StepTime units per second) is shown as 240 km/h
  GuiText(ProfX, y, Format('Segments: %d   Lap length: %.2f km   End height: %.1f',
          [Length(Segments), Length(Segments) * SegLen / (SegLen / StepTime) * (240 / 3.6) / 1000, endH]));
  if not OwnTrack then
    GuiText(ProfX, y + 16, 'Track is too short (under 100 segments) - the game would use the built-in track.',
            1, 255, 120, 90)
  else if Abs(endH) > 0.5 then
    GuiText(ProfX, y + 16, 'The lap does not end at ground level - add "downhill" as the last section.',
            1, 255, 120, 90)
  else
    GuiText(ProfX, y + 16, 'The lap closes at ground level.', 1, 120, 220, 140);
end;

procedure DrawPreview;
var
  dst: TSDL_FRect;
  y: Single;
begin
  if PreviewTex <> nil then
  begin
    SDL_SetRenderTarget(Ren, PreviewTex);
    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    RenderWorld(Cam, PreviewZ, 0, True, PlayerColor, 0, 0);
    SDL_SetRenderTarget(Ren, nil);
    dst.x := PrevX; dst.y := PrevY; dst.w := PrevW; dst.h := PrevH;
    SDL_RenderTexture(Ren, PreviewTex, nil, @dst);
  end;
  GuiColor(70, 78, 92);
  GuiFrame(PrevX, PrevY, PrevW, PrevH);

  y := PrevY + PrevH + 10;
  if GuiButton(PrevX, y, 110, 26, 'Play (Space)', Playing) then Playing := not Playing;
  if GuiButton(PrevX + 118, y, 140, 26, 'Go to section (J)') then JumpToSection;
  GuiSlider(PrevX + 270, y - 2, 158, 'Preview speed', PlaySpeed, 0.05, 1, 2);
end;

procedure DrawUI;
begin
  GuiColor(16, 18, 24);
  GuiFill(0, 0, WinW, WinH);
  GuiText(20, 14, 'TRACK EDITOR', 2, 255, 210, 80);
  GuiText(240, 20, DataDir + 'track.txt');
  if Dirty then GuiText(WinW - 150, 20, '* not saved', 1, 255, 140, 90);

  DrawList;
  DrawSectionEditor;

  DrawMinimap(MapX0, MapY0, MapS, PreviewZ, True, SectionFirst(Sel), SectionLast(Sel), 255);
  GuiColor(70, 78, 92);
  GuiFrame(MapX0, MapY0, MapS, MapS);
  GuiText(MapX0, MapY0 + MapS + 6, 'Map: yellow = selected section, white = start line', 1, 170, 175, 190);

  DrawPreview;
  DrawProfile;
  DrawInfo;

  if GuiButton(20, WinH - 44, 110, 30, 'Save (F2)') then DoSave;
  if GuiButton(138, WinH - 44, 110, 30, 'Reload (F5)') then DoReload;
  if GuiButton(256, WinH - 44, 164, 30, 'Built-in track') then
  begin
    Secs := DefaultTrackSections;
    Sel := 0;
    ListTop := 0;
    Changed;
    SetStatus('Built-in track restored (not saved yet)');
  end;
  if StatusTime > 0 then GuiText(440, WinH - 32, Status, 1, 255, 220, 120)
  else GuiText(440, WinH - 32, 'Shift + / - = bigger steps.  Click the height profile to move the preview.',
               1, 170, 175, 190);
end;

var
  Ev: TSDL_Event;
  Running: Boolean;
  Freq, LastTick, NowTick: UInt64;
  FrameTime: Double;
  sc: TSDL_Scancode;
  renderer: PSDL_Renderer;
  i: Integer;
  travelled: Double;

begin
  Randomize;
  InitCommon;
  InitWorld;
  LoadAllData(True);
  MaxSpeed := SegLen / StepTime;

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  renderer := nil;
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Track editor', WinW, WinH, 0, @Win, @renderer) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  Ren := renderer;
  GuiRen := renderer;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  PreviewTex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET,
                                  ScreenW, ScreenH);

  ReloadWorldGraphics;
  DoReload;
  Status := '';
  StatusTime := 0;

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
        else if sc = SDL_SCANCODE_SPACE then Playing := not Playing
        else if sc = SDL_SCANCODE_J then JumpToSection
        else if (sc = SDL_SCANCODE_UP) and (Sel > 0) then
        begin
          Dec(Sel);
          KeepSelVisible;
          if not Playing then JumpToSection;
        end
        else if (sc = SDL_SCANCODE_DOWN) and (Sel < High(Secs)) then
        begin
          Inc(Sel);
          KeepSelVisible;
          if not Playing then JumpToSection;
        end
        else if sc = SDL_SCANCODE_F2 then DoSave
        else if sc = SDL_SCANCODE_F5 then DoReload;
      end;
    end;

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;

    if Playing and (TrackLength > 0) then
    begin
      travelled := PlaySpeed * MaxSpeed * FrameTime;
      PreviewZ := Increase(PreviewZ, travelled, TrackLength);
      SkyOffset := WrapUnit(SkyOffset + 0.001 * Segments[FindSegment(PreviewZ)].curve * travelled / SegLen);
      HillOffset := WrapUnit(HillOffset + 0.002 * Segments[FindSegment(PreviewZ)].curve * travelled / SegLen);
    end;
    for i := 0 to High(Cars) do
      Cars[i].z := Increase(Cars[i].z, Cars[i].speed * FrameTime, TrackLength);

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    DrawUI;
    SDL_RenderPresent(Ren);
  end;

  FreeTextures;
  if PreviewTex <> nil then SDL_DestroyTexture(PreviewTex);
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
