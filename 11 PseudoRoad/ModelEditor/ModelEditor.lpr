program ModelEditor;

{ Pseudo 3D Road - vehicle model editor.
  Left: the model files in data\models. Middle: the .car file as text -
  type to edit it. Right: the model in 3D, rebuilt as you type. The parts
  made by the line under the cursor glow yellow. Problems in the file are
  listed under the view (click one to jump to its line).
  "On the road" drives the model on the real track among the traffic.

  Keys: type in the text after clicking it; F2 save, F5 reload,
        Esc leaves the text (press again to quit). Drag the view to turn
        the model, mouse wheel zooms. Space toggles spinning (outside text). }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Classes, Math, SDL3, p3d_common, p3d_world, p3d_gui;

const
  WinW = 1280;
  WinH = 800;
  FilesX = 10;
  FilesY = 70;
  FilesW = 160;
  TextX = 180;
  TextY = 50;
  TextW = 610;
  TextH = 692;
  LineH = 13;
  Gutter = 40;
  ViewX = 800;
  ViewY = 50;
  ViewW = 470;
  ViewH = 352;

var
  Win: PSDL_Window = nil;
  ViewTex: PSDL_Texture = nil;
  Lines, Warnings, FileNames: TStringList;
  WarnRow: array of Boolean;
  CurKey: string = 'sedan';
  CurRow: Integer = 0;
  CurCol: Integer = 0;
  TopRow: Integer = 0;
  LeftCol: Integer = 0;
  TextFocus: Boolean = False;
  Dirty: Boolean = False;
  NeedParse: Boolean = True;
  EditModel: TModel;
  EditIdx: Integer = 0;
  Angle: Double = 0.6;
  Pitch: Double = 18;
  Zoom: Double = 1;
  AutoSpin: Boolean = False;
  RoadMode: Boolean = False;
  Paint: TRGB;
  CarZ: Double = 0;
  MaxSpeed: Double;
  DragOn: Boolean = False;
  DragX, DragY: Single;
  Status: string = '';
  StatusTime: Double = 0;
  NameMode: Boolean = False;
  NameBuf: string = '';
  PendingOpen: string = '';
  QuitAsked: Boolean = False;
  BlinkT: Double = 0;
  Running: Boolean = True;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 5;
end;

function VisRows: Integer;
begin
  Result := TextH div LineH;
end;

function VisCols: Integer;
begin
  Result := (TextW - Gutter - 8) div 8;
end;

{ ------------------------------------------------------------- files }

procedure ScanFiles;
var
  sr: TSearchRec;
begin
  FileNames.Clear;
  if FindFirst(DataDir + 'models' + DirectorySeparator + '*.car', faAnyFile, sr) = 0 then
  begin
    repeat
      FileNames.Add(ChangeFileExt(sr.Name, ''));
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  FileNames.Sort;
end;

procedure OpenModel(const key: string);
begin
  try
    Lines.LoadFromFile(ModelPath(key));
  except
    Lines.Clear;
  end;
  if Lines.Count = 0 then Lines.Add('');
  CurKey := LowerCase(key);
  CurRow := 0; CurCol := 0; TopRow := 0; LeftCol := 0;
  Dirty := False;
  NeedParse := True;
  PendingOpen := '';
  Paint := PlayerColor;
end;

procedure SaveModelAs(const key: string);
begin
  try
    Lines.SaveToFile(ModelPath(key));
    CurKey := LowerCase(key);
    Dirty := False;
    ScanFiles;
    NeedParse := True;
    SetStatus('Saved ' + ModelPath(key));
  except
    on E: Exception do SetStatus('Could not save: ' + E.Message);
  end;
end;

procedure Parse;
var
  M: TModel;
  i, n, p, code: Integer;
  s: string;
begin
  Warnings.Clear;
  LoadModelLines(Lines, CurKey, M, Warnings);
  EditModel := M;

  // put it into the world list so the road view (and traffic) use it
  EditIdx := -1;
  for i := 0 to High(Models) do
    if SameText(Models[i].key, CurKey) then EditIdx := i;
  if EditIdx < 0 then
  begin
    EditIdx := Length(Models);
    SetLength(Models, EditIdx + 1);
  end;
  Models[EditIdx] := M;
  PlayerModel := EditIdx;

  // which rows have a warning
  SetLength(WarnRow, Lines.Count);
  for i := 0 to High(WarnRow) do WarnRow[i] := False;
  for i := 0 to Warnings.Count - 1 do
  begin
    s := Warnings[i];
    if Copy(s, 1, 5) <> 'line ' then Continue;
    p := Pos(':', s);
    Val(Copy(s, 6, p - 6), n, code);
    if (code = 0) and (n >= 1) and (n <= Length(WarnRow)) then WarnRow[n - 1] := True;
  end;
  NeedParse := False;
end;

{ ----------------------------------------------------------- text editing }

procedure ClampCursor;
begin
  if Lines.Count = 0 then Lines.Add('');
  CurRow := EnsureRange(CurRow, 0, Lines.Count - 1);
  CurCol := EnsureRange(CurCol, 0, Length(Lines[CurRow]));
end;

procedure KeepCursorVisible;
begin
  if CurRow < TopRow then TopRow := CurRow;
  if CurRow >= TopRow + VisRows then TopRow := CurRow - VisRows + 1;
  if CurCol < LeftCol then LeftCol := Max(0, CurCol - 8);
  if CurCol >= LeftCol + VisCols then LeftCol := CurCol - VisCols + 8;
  TopRow := EnsureRange(TopRow, 0, Max(0, Lines.Count - 1));
end;

procedure TextChanged;
begin
  Dirty := True;
  NeedParse := True;
  QuitAsked := False;
end;

procedure InsertText(const s: string);
var
  line: string;
begin
  ClampCursor;
  line := Lines[CurRow];
  Insert(s, line, CurCol + 1);
  Lines[CurRow] := line;
  CurCol := CurCol + Length(s);
  TextChanged;
end;

procedure Backspace;
var
  line: string;
  prevLen: Integer;
begin
  ClampCursor;
  line := Lines[CurRow];
  if CurCol > 0 then
  begin
    Delete(line, CurCol, 1);
    Lines[CurRow] := line;
    Dec(CurCol);
  end
  else if CurRow > 0 then
  begin
    prevLen := Length(Lines[CurRow - 1]);
    Lines[CurRow - 1] := Lines[CurRow - 1] + line;
    Lines.Delete(CurRow);
    Dec(CurRow);
    CurCol := prevLen;
  end
  else Exit;
  TextChanged;
end;

procedure DeleteForward;
var
  line: string;
begin
  ClampCursor;
  line := Lines[CurRow];
  if CurCol < Length(line) then
  begin
    Delete(line, CurCol + 1, 1);
    Lines[CurRow] := line;
  end
  else if CurRow < Lines.Count - 1 then
  begin
    Lines[CurRow] := line + Lines[CurRow + 1];
    Lines.Delete(CurRow + 1);
  end
  else Exit;
  TextChanged;
end;

procedure NewLine;
var
  line: string;
begin
  ClampCursor;
  line := Lines[CurRow];
  Lines[CurRow] := Copy(line, 1, CurCol);
  Lines.Insert(CurRow + 1, Copy(line, CurCol + 1, MaxInt));
  Inc(CurRow);
  CurCol := 0;
  TextChanged;
end;

procedure TextKey(sc: TSDL_Scancode);
begin
  if sc = SDL_SCANCODE_BACKSPACE then Backspace
  else if sc = SDL_SCANCODE_DELETE then DeleteForward
  else if (sc = SDL_SCANCODE_RETURN) or (sc = SDL_SCANCODE_KP_ENTER) then NewLine
  else if sc = SDL_SCANCODE_TAB then InsertText('  ')
  else if sc = SDL_SCANCODE_LEFT then
  begin
    if CurCol > 0 then Dec(CurCol)
    else if CurRow > 0 then
    begin
      Dec(CurRow);
      CurCol := Length(Lines[CurRow]);
    end;
  end
  else if sc = SDL_SCANCODE_RIGHT then
  begin
    if CurCol < Length(Lines[CurRow]) then Inc(CurCol)
    else if CurRow < Lines.Count - 1 then
    begin
      Inc(CurRow);
      CurCol := 0;
    end;
  end
  else if sc = SDL_SCANCODE_UP then Dec(CurRow)
  else if sc = SDL_SCANCODE_DOWN then Inc(CurRow)
  else if sc = SDL_SCANCODE_HOME then CurCol := 0
  else if sc = SDL_SCANCODE_END then CurCol := MaxInt
  else if sc = SDL_SCANCODE_PAGEUP then CurRow := CurRow - VisRows
  else if sc = SDL_SCANCODE_PAGEDOWN then CurRow := CurRow + VisRows;
  ClampCursor;
  KeepCursorVisible;
  BlinkT := 0;
end;

{ --------------------------------------------------------------- drawing }

procedure DrawFiles;
var
  i: Integer;
  y: Single;
begin
  GuiText(FilesX, FilesY - 18, 'Models', 1, 255, 210, 80);
  for i := 0 to FileNames.Count - 1 do
  begin
    y := FilesY + i * 22;
    if y > WinH - 120 then Break;
    if GuiButton(FilesX, y, FilesW, 20, FileNames[i], SameText(FileNames[i], CurKey)) then
    begin
      if Dirty and (PendingOpen <> FileNames[i]) then
      begin
        PendingOpen := FileNames[i];
        SetStatus('Unsaved changes - click ' + FileNames[i] + ' again to discard them');
      end
      else
      begin
        OpenModel(FileNames[i]);
        SetStatus('Opened ' + ModelPath(CurKey));
      end;
    end;
  end;
end;

procedure DrawTextArea;
var
  r, row, n, sp: Integer;
  y, cx: Single;
  line, vis, cmdw: string;
begin
  GuiColor(20, 23, 30);
  GuiFill(TextX, TextY, TextW, TextH);
  GuiColor(28, 32, 42);
  GuiFill(TextX, TextY, Gutter - 4, TextH);

  if GuiInside(TextX, TextY, TextW, TextH) then
  begin
    if WheelY <> 0 then
      TopRow := EnsureRange(TopRow - Round(WheelY) * 3, 0, Max(0, Lines.Count - 1));
    if MousePressed then
    begin
      TextFocus := True;
      CurRow := TopRow + Trunc((MouseY - TextY) / LineH);
      CurCol := LeftCol + Round((MouseX - TextX - Gutter) / 8);
      ClampCursor;
      BlinkT := 0;
    end;
  end
  else if MousePressed and not NameMode then
    TextFocus := False;

  for r := 0 to VisRows - 1 do
  begin
    row := TopRow + r;
    if row >= Lines.Count then Break;
    y := TextY + r * LineH + 2;
    if row = CurRow then
    begin
      GuiColor(255, 230, 0, 28);
      GuiFill(TextX + Gutter - 4, y - 2, TextW - Gutter + 4, LineH);
    end;
    if (row < Length(WarnRow)) and WarnRow[row] then
    begin
      GuiColor(230, 60, 50);
      GuiFill(TextX, y - 2, 4, LineH);
    end;
    GuiText(TextX + 4, y, Format('%3d', [row + 1]), 1, 110, 116, 130);

    line := Lines[row];
    vis := Copy(line, LeftCol + 1, VisCols);
    if (Length(Trim(line)) > 0) and (Trim(line)[1] = '#') then
      GuiText(TextX + Gutter, y, vis, 1, 120, 150, 120)
    else
    begin
      GuiText(TextX + Gutter, y, vis, 1, 225, 228, 235);
      if LeftCol = 0 then
      begin
        sp := Pos(' ', line);
        if sp = 0 then cmdw := line else cmdw := Copy(line, 1, sp - 1);
        GuiText(TextX + Gutter, y, cmdw, 1, 255, 200, 90);
      end;
    end;
  end;

  // cursor
  if TextFocus and (Frac(BlinkT) < 0.6) and (CurRow >= TopRow) and (CurRow < TopRow + VisRows) then
  begin
    cx := TextX + Gutter + (CurCol - LeftCol) * 8;
    GuiColor(255, 255, 255);
    GuiFill(cx, TextY + (CurRow - TopRow) * LineH, 2, LineH);
  end;

  if TextFocus then GuiColor(255, 200, 40) else GuiColor(70, 78, 92);
  GuiFrame(TextX, TextY, TextW, TextH);
  n := Lines.Count;
  GuiText(TextX, TextY + TextH + 4, Format('%s.car   line %d/%d  col %d', [CurKey, CurRow + 1, n, CurCol + 1]),
          1, 170, 175, 190);
end;

procedure DrawGround(dc, hc: Double);
var
  i: Integer;
  z0, z1, x, z, f0, f1: Double;
begin
  // ground lines every 200 units, as seen from the camera
  SDL_SetRenderDrawColor(Ren, 120, 126, 134, 255);
  z0 := MaxD(dc - 2400, 120);
  z1 := dc + 2400;
  for i := -12 to 12 do
  begin
    x := i * 200;
    f0 := ViewDepth * (ScreenW / 2) / z0;
    f1 := ViewDepth * (ScreenW / 2) / z1;
    SDL_RenderLine(Ren, ViewCX + x * f0, ViewCY + hc * f0, ViewCX + x * f1, ViewCY + hc * f1);
  end;
  for i := -12 to 12 do
  begin
    z := dc + i * 200;
    if z < 120 then Continue;
    f0 := ViewDepth * (ScreenW / 2) / z;
    SDL_RenderLine(Ren, ViewCX - 2400 * f0, ViewCY + hc * f0, ViewCX + 2400 * f0, ViewCY + hc * f0);
  end;
end;

procedure RenderView;
var
  y: Integer;
  dc, hc, cz, u, L: Double;
  dst: TSDL_FRect;
begin
  if ViewTex = nil then Exit;
  SDL_SetRenderTarget(Ren, ViewTex);
  SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
  SDL_RenderClear(Ren);

  if RoadMode then
    RenderWorld(Cam, CarZ, 0, True, Paint, 0, 0)
  else
  begin
    ViewDepth := CameraDepth;
    ViewCX := ScreenW / 2;
    ViewCY := ScreenH * 0.32;
    y := 0;
    while y < ScreenH do
    begin
      if y < ViewCY then SetCol(Mix(MakeRGB(70, 100, 150), MakeRGB(170, 195, 220), y / ViewCY))
      else SetCol(Mix(MakeRGB(92, 98, 104), MakeRGB(60, 64, 70), (y - ViewCY) / (ScreenH - ViewCY)));
      FillR(0, y, ScreenW, 4);
      Inc(y, 4);
    end;
    L := MaxD(EditModel.length, 100);
    dc := MaxD(L, EditModel.width) * 1.6 * Zoom + 400;     // camera to model centre
    if dc < L / 2 + 200 then dc := L / 2 + 200;
    hc := dc * Tan(Pitch * Pi / 180);                      // camera height
    DrawGround(dc, hc);
    cz := dc - L / 2;                                      // camera to the rear
    u := ViewDepth * (ScreenW / 2) / cz;
    DrawCarAngle(EditModel, ViewCX, ViewCY + hc * u, u, Paint, 1, Angle, ScreenH);
  end;

  SDL_SetRenderTarget(Ren, nil);
  dst.x := ViewX; dst.y := ViewY; dst.w := ViewW; dst.h := ViewH;
  SDL_RenderTexture(Ren, ViewTex, nil, @dst);
  GuiColor(70, 78, 92);
  GuiFrame(ViewX, ViewY, ViewW, ViewH);
end;

procedure DrawViewControls;
var
  y, x: Single;
  i, n, code: Integer;
  pal: TRGBArray;
  s: string;
begin
  // mouse on the view
  if not RoadMode and GuiInside(ViewX, ViewY, ViewW, ViewH) then
  begin
    if MousePressed then
    begin
      DragOn := True;
      DragX := MouseX;
      DragY := MouseY;
    end;
    if WheelY <> 0 then Zoom := ClampD(Zoom * (1 - WheelY * 0.1), 0.4, 3);
  end;
  if DragOn then
  begin
    if MouseDown then
    begin
      Angle := Angle + (MouseX - DragX) * 0.01;
      Pitch := ClampD(Pitch - (MouseY - DragY) * 0.2, 2, 60);
      DragX := MouseX;
      DragY := MouseY;
    end
    else DragOn := False;
  end;

  y := ViewY + ViewH + 8;
  if GuiButton(ViewX, y, 150, 24, 'Model view', not RoadMode) then RoadMode := False;
  if GuiButton(ViewX + 156, y, 150, 24, 'On the road', RoadMode) then RoadMode := True;
  if GuiButton(ViewX + 312, y, 158, 24, 'Spin (Space)', AutoSpin) then AutoSpin := not AutoSpin;
  y := y + 30;
  if GuiButton(ViewX, y, 112, 22, 'Rear') then Angle := 0;
  if GuiButton(ViewX + 119, y, 112, 22, 'Side') then Angle := Pi / 2;
  if GuiButton(ViewX + 238, y, 112, 22, 'Front') then Angle := Pi;
  if GuiButton(ViewX + 357, y, 113, 22, '3/4') then Angle := 0.6;
  y := y + 30;
  GuiSlider(ViewX, y, 228, 'Look down (deg)', Pitch, 2, 60, 0);
  GuiSlider(ViewX + 242, y, 228, 'Zoom', Zoom, 0.4, 3, 2);
  y := y + 36;

  // paint
  GuiText(ViewX, y + 6, 'Paint');
  if Length(EditModel.palette) > 0 then pal := EditModel.palette else pal := CarPalette;
  x := ViewX + 50;
  for i := 0 to Min(High(pal), 13) do
  begin
    SetCol(pal[i]);
    FillR(x, y, 24, 20);
    if (pal[i].r = Paint.r) and (pal[i].g = Paint.g) and (pal[i].b = Paint.b) then GuiColor(255, 255, 255)
    else GuiColor(70, 78, 92);
    GuiFrame(x - 1, y - 1, 26, 22);
    if MousePressed and GuiInside(x, y, 24, 20) then Paint := pal[i];
    x := x + 30;
  end;
  y := y + 30;

  // info
  GuiText(ViewX, y, Format('%s   L %.0f  W %.0f  H %.0f   hit %.0f   speed %.2f',
          [EditModel.name, EditModel.length, EditModel.width, EditModel.height, EditModel.hit, EditModel.speed]));
  GuiText(ViewX, y + 14, Format('%d faces, %d decals   (yellow = parts of line %d)',
          [Length(EditModel.faces), Length(EditModel.decals), CurRow + 1]), 1, 170, 175, 190);
  y := y + 34;

  // problems
  if Warnings.Count = 0 then
    GuiText(ViewX, y, 'No problems found.', 1, 120, 220, 140)
  else
  begin
    GuiText(ViewX, y, Format('%d problem(s) - click to jump:', [Warnings.Count]), 1, 255, 140, 90);
    n := Min(Warnings.Count, 8);
    for i := 0 to n - 1 do
    begin
      s := Warnings[i];
      if Length(s) > 58 then s := Copy(s, 1, 56) + '..';
      GuiText(ViewX, y + 16 + i * 14, s, 1, 255, 170, 150);
      if MousePressed and GuiInside(ViewX, y + 14 + i * 14, ViewW, 14) and (Copy(Warnings[i], 1, 5) = 'line ') then
      begin
        Val(Copy(Warnings[i], 6, Pos(':', Warnings[i]) - 6), CurRow, code);
        CurRow := CurRow - 1;
        CurCol := 0;
        ClampCursor;
        KeepCursorVisible;
        TextFocus := True;
      end;
    end;
  end;
end;

procedure DrawNameBox;
begin
  GuiColor(0, 0, 0, 150);
  GuiFill(0, 0, WinW, WinH);
  GuiPanel(WinW / 2 - 220, WinH / 2 - 70, 440, 140, 'Save as new model');
  GuiText(WinW / 2 - 200, WinH / 2 - 26, 'Name (letters, digits, - and _):');
  GuiColor(20, 23, 30);
  GuiFill(WinW / 2 - 200, WinH / 2 - 8, 400, 26);
  GuiText(WinW / 2 - 192, WinH / 2 - 1, NameBuf + '_', 1.5, 255, 230, 120);
  GuiText(WinW / 2 - 200, WinH / 2 + 34, 'Enter = save    Esc = cancel', 1, 170, 175, 190);
end;

procedure DrawUI;
var
  y: Single;
begin
  GuiColor(16, 18, 24);
  GuiFill(0, 0, WinW, WinH);
  GuiText(10, 14, 'MODEL EDITOR', 2, 255, 210, 80);
  GuiText(230, 20, ModelPath(CurKey));
  if Dirty then GuiText(WinW - 150, 20, '* not saved', 1, 255, 140, 90);

  DrawFiles;
  DrawTextArea;
  HighlightLine := CurRow;
  RenderView;
  DrawViewControls;

  y := WinH - 38;
  if GuiButton(FilesX, y, 76, 28, 'Save F2') then SaveModelAs(CurKey);
  if GuiButton(FilesX + 84, y, 76, 28, 'Save as') then
  begin
    NameMode := True;
    NameBuf := '';
  end;
  if GuiButton(FilesX, y - 34, 76, 28, 'Reload') then
  begin
    OpenModel(CurKey);
    SetStatus('Reloaded ' + ModelPath(CurKey));
  end;
  if GuiButton(FilesX + 84, y - 34, 76, 28, 'Defaults') then
  begin
    WriteDefaultModels(False);
    ScanFiles;
    SetStatus('Missing default models were written again');
  end;
  if GuiButton(TextX + 300, TextY + TextH + 2, 150, 18, 'Duplicate line') then
  begin
    ClampCursor;
    Lines.Insert(CurRow + 1, Lines[CurRow]);
    Inc(CurRow);
    TextChanged;
  end;
  if GuiButton(TextX + 460, TextY + TextH + 2, 150, 18, 'Delete line') then
  begin
    ClampCursor;
    if Lines.Count > 1 then Lines.Delete(CurRow) else Lines[0] := '';
    ClampCursor;
    TextChanged;
  end;
  if StatusTime > 0 then GuiText(TextX, WinH - 20, Status, 1, 255, 220, 120);

  if NameMode then DrawNameBox;
end;

{ ----------------------------------------------------------------- main }

procedure HandleKey(sc: TSDL_Scancode);
var
  key: string;
begin
  if NameMode then
  begin
    if sc = SDL_SCANCODE_ESCAPE then NameMode := False
    else if sc = SDL_SCANCODE_BACKSPACE then Delete(NameBuf, Length(NameBuf), 1)
    else if (sc = SDL_SCANCODE_RETURN) or (sc = SDL_SCANCODE_KP_ENTER) then
    begin
      key := LowerCase(Trim(NameBuf));
      NameMode := False;
      if key <> '' then SaveModelAs(key);
    end;
    Exit;
  end;

  if sc = SDL_SCANCODE_F2 then SaveModelAs(CurKey)
  else if sc = SDL_SCANCODE_F5 then
  begin
    OpenModel(CurKey);
    SetStatus('Reloaded ' + ModelPath(CurKey));
  end
  else if TextFocus then
  begin
    if sc = SDL_SCANCODE_ESCAPE then TextFocus := False
    else TextKey(sc);
  end
  else if sc = SDL_SCANCODE_SPACE then AutoSpin := not AutoSpin
  else if sc = SDL_SCANCODE_ESCAPE then
  begin
    if Dirty and not QuitAsked then
    begin
      QuitAsked := True;
      SetStatus('Unsaved changes - press Esc again to quit without saving');
    end
    else Running := False;
  end;
end;

procedure HandleText(const s: string);
var
  i: Integer;
begin
  if NameMode then
  begin
    for i := 1 to Length(s) do
      if (s[i] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']) and (Length(NameBuf) < 32) then
        NameBuf := NameBuf + s[i];
  end
  else if TextFocus then
  begin
    InsertText(s);
    KeepCursorVisible;
    BlinkT := 0;
  end;
end;

var
  Ev: TSDL_Event;
  Freq, LastTick, NowTick: UInt64;
  FrameTime: Double;
  renderer: PSDL_Renderer;
  i: Integer;

begin
  Randomize;
  InitCommon;
  InitWorld;
  LoadAllData(True);
  MaxSpeed := SegLen / StepTime;
  Lines := TStringList.Create;
  Warnings := TStringList.Create;
  FileNames := TStringList.Create;

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  renderer := nil;
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Model editor', WinW, WinH, 0, @Win, @renderer) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  Ren := renderer;
  GuiRen := renderer;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  ViewTex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, ScreenW, ScreenH);
  SDL_StartTextInput(Win);

  ReloadWorldGraphics;
  BuildTrackFromFile(99);
  ResetTraffic(MaxSpeed);
  ScanFiles;
  if FileNames.IndexOf(PlayerModelName) >= 0 then OpenModel(PlayerModelName)
  else if FileNames.Count > 0 then OpenModel(FileNames[0])
  else OpenModel('sedan');

  Freq := SDL_GetPerformanceFrequency;
  LastTick := SDL_GetPerformanceCounter;
  while Running do
  begin
    GuiBeginFrame;
    while SDL_PollEvent(@Ev) do
    begin
      GuiEvent(Ev);
      if Ev._type = SDL_EVENT_QUIT then Running := False
      else if Ev._type = SDL_EVENT_KEY_DOWN then HandleKey(Ev.key.scancode)
      else if Ev._type = SDL_EVENT_TEXT_INPUT then HandleText(string(Ev.text.text));
    end;

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if FrameTime > 0.25 then FrameTime := 0.25;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;
    BlinkT := BlinkT + FrameTime;
    if AutoSpin and not RoadMode then Angle := Angle + FrameTime * 0.8;

    if NeedParse then Parse;

    if RoadMode then
    begin
      CarZ := Increase(CarZ, 0.45 * MaxSpeed * FrameTime, TrackLength);
      for i := 0 to High(Cars) do
        Cars[i].z := Increase(Cars[i].z, Cars[i].speed * FrameTime, TrackLength);
    end;

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    DrawUI;
    SDL_RenderPresent(Ren);
  end;

  SDL_StopTextInput(Win);
  FreeTextures;
  if ViewTex <> nil then SDL_DestroyTexture(ViewTex);
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
