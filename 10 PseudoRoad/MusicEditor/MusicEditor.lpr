program MusicEditor;

{ Pseudo 3D Road - music editor.
  Opens data\music.ini and shows the melody as a piano roll
  (16 steps per bar). Click a cell to place a note, click it again to turn
  it into "hold", right-click to place a rest. Each bar has a bass root and
  a chord. Play / Stop plays the song exactly as the game does.

  Keys: Space play/stop, Left/Right page, F2 save, F5 reload, Esc quit }

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$APPTYPE GUI}

uses
  SysUtils, Math, SDL3, p3d_common, p3d_audio, p3d_gui;

const
  WinW = 1100;
  WinH = 720;
  GridX = 70;
  GridY = 110;
  CellW = 15;
  CellH = 11;
  NoteHi = 88;                   // E6
  NoteLo = 55;                   // G3
  PageSteps = 64;                // 4 bars visible

  QualNames: array[0..5] of string = ('', 'm', '7', 'm7', 'sus4', 'dim');
  QualSize: array[0..5] of Integer = (3, 3, 4, 4, 3, 3);
  QualIv: array[0..5, 0..3] of Integer = (
    (0, 4, 7, 0), (0, 3, 7, 0), (0, 4, 7, 10), (0, 3, 7, 10), (0, 5, 7, 0), (0, 3, 6, 0));
  Letters: array[0..11] of string = ('C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B');

var
  Win: PSDL_Window = nil;
  Ren: PSDL_Renderer = nil;
  Page: Integer = 0;
  Playing: Boolean = False;
  GameMusicOn: Boolean = True;   // the "enabled" value stored in music.ini
  Status: string = '';
  StatusTime: Double = 0;
  Dirty: Boolean = False;

procedure SetStatus(const s: string);
begin
  Status := s;
  StatusTime := 4;
end;

function Bars: Integer;
begin
  Result := Max(1, (Length(Melody) + 15) div 16);
end;

{ melody, bass and chords always cover the same number of bars }
procedure NormaliseSong;
var
  n, i, old, j: Integer;
begin
  n := Bars;
  old := Length(Melody);
  SetLength(Melody, n * 16);
  for i := old to n * 16 - 1 do Melody[i] := 0;

  old := Length(BassRoots);
  if old = 0 then
  begin
    SetLength(BassRoots, 1);
    BassRoots[0] := 45;
    old := 1;
  end;
  SetLength(BassRoots, n);
  for i := old to n - 1 do BassRoots[i] := BassRoots[i mod old];

  old := Length(Chords);
  if old = 0 then
  begin
    SetLength(Chords, 1);
    SetLength(Chords[0], 3);
    Chords[0][0] := 57; Chords[0][1] := 60; Chords[0][2] := 64;
    old := 1;
  end;
  SetLength(Chords, n);
  for i := old to n - 1 do
  begin
    SetLength(Chords[i], Length(Chords[i mod old]));
    for j := 0 to High(Chords[i]) do Chords[i][j] := Chords[i mod old][j];
  end;
  if Page * PageSteps >= n * 16 then Page := 0;
end;

function ChordQuality(const ch: TIntArray; out root: Integer): Integer;
var
  i, j, q, lo: Integer;
  have: array[0..11] of Boolean;
  ok: Boolean;
begin
  Result := -1;
  root := 0;
  if Length(ch) = 0 then Exit;
  lo := ch[0];
  for i := 1 to High(ch) do lo := Min(lo, ch[i]);
  root := lo;
  for i := 0 to 11 do have[i] := False;
  for i := 0 to High(ch) do have[((ch[i] - lo) mod 12 + 12) mod 12] := True;
  for q := 0 to 5 do
  begin
    ok := True;
    for i := 0 to 11 do
    begin
      if not have[i] then Continue;
      ok := False;
      for j := 0 to QualSize[q] - 1 do
        if QualIv[q, j] = i then ok := True;
      if not ok then Break;
    end;
    if ok then
      for j := 0 to QualSize[q] - 1 do
        if not have[QualIv[q, j]] then ok := False;
    if ok then Exit(q);
  end;
end;

function ChordName(bar: Integer): string;
var
  q, root: Integer;
begin
  q := ChordQuality(Chords[bar], root);
  if q < 0 then Result := 'custom ' + IntsToStr(Chords[bar], ',')
  else Result := Letters[root mod 12] + QualNames[q];
end;

procedure SetChord(bar, q: Integer);
var
  root, j: Integer;
begin
  root := 48 + (BassRoots[bar] mod 12);
  if root < 52 then root := root + 12;
  SetLength(Chords[bar], QualSize[q]);
  for j := 0 to QualSize[q] - 1 do Chords[bar][j] := root + QualIv[q, j];
end;

procedure DoSave;
var
  playingNow: Boolean;
begin
  NormaliseSong;
  playingNow := MusicOn;
  MusicOn := GameMusicOn;
  try
    SaveMusic(DataDir + 'music.ini');
    Dirty := False;
    SetStatus('Saved data\music.ini');
  except
    on E: Exception do SetStatus('Could not save: ' + E.Message);
  end;
  MusicOn := playingNow;
end;

procedure DoReload;
begin
  SetDefaultMusic;
  try
    if FileExists(DataDir + 'music.ini') then LoadMusic(DataDir + 'music.ini');
  except
  end;
  GameMusicOn := MusicOn;
  MusicOn := Playing;
  NormaliseSong;
  RecalcMusic;
  Dirty := False;
  SetStatus('Reloaded data\music.ini');
end;

procedure DoDefaults;
begin
  SetDefaultMusic;
  GameMusicOn := MusicOn;
  MusicOn := Playing;
  NormaliseSong;
  RecalcMusic;
  Dirty := True;
  SetStatus('Built-in song restored (not saved yet)');
end;

procedure TogglePlay;
begin
  Playing := not Playing;
  MusicOn := Playing;
  if Playing then ResetMusic;
end;

procedure DrawGrid;
var
  sounding: TIntArray;
  i, col, row, s, note, cur, total, playStep: Integer;
  x, y: Single;
  black: Boolean;
begin
  total := Length(Melody);
  SetLength(sounding, total);
  cur := -1;
  for i := 0 to total - 1 do
  begin
    if Melody[i] > 0 then cur := Melody[i]
    else if Melody[i] < 0 then cur := -1;
    sounding[i] := cur;
  end;

  // rows and note names
  for row := 0 to NoteHi - NoteLo do
  begin
    note := NoteHi - row;
    y := GridY + row * CellH;
    black := (note mod 12) in [1, 3, 6, 8, 10];
    if black then GuiColor(26, 29, 37) else GuiColor(34, 38, 48);
    GuiFill(GridX, y, PageSteps * CellW, CellH - 1);
    if (note mod 12 = 0) or (note mod 12 = 9) or (row = 0) then
      GuiText(GridX - 40, y + 2, NoteName(note), 1, 170, 175, 190);
  end;

  // bar and beat lines
  for col := 0 to PageSteps do
  begin
    if col mod 16 = 0 then GuiColor(120, 130, 150)
    else if col mod 4 = 0 then GuiColor(60, 66, 80)
    else Continue;
    GuiFill(GridX + col * CellW, GridY, 1, (NoteHi - NoteLo + 1) * CellH + 16);
  end;

  // playhead
  if Playing and (total > 0) then
  begin
    playStep := MusicCurrentStep mod total;
    if (playStep >= Page * PageSteps) and (playStep < (Page + 1) * PageSteps) then
    begin
      GuiColor(255, 255, 255, 40);
      GuiFill(GridX + (playStep - Page * PageSteps) * CellW, GridY, CellW, (NoteHi - NoteLo + 1) * CellH);
    end;
  end;

  // notes
  for col := 0 to PageSteps - 1 do
  begin
    s := Page * PageSteps + col;
    if s >= total then Break;
    x := GridX + col * CellW;
    note := sounding[s];
    if (note >= NoteLo) and (note <= NoteHi) then
    begin
      y := GridY + (NoteHi - note) * CellH;
      if Melody[s] > 0 then GuiColor(255, 170, 40) else GuiColor(170, 110, 30);
      GuiFill(x + 1, y + 1, CellW - 1, CellH - 3);
    end;
    // step lane: on / hold / rest
    y := GridY + (NoteHi - NoteLo + 1) * CellH + 3;
    if Melody[s] > 0 then GuiColor(255, 170, 40)
    else if Melody[s] < 0 then GuiColor(200, 60, 60)
    else GuiColor(70, 76, 90);
    GuiFill(x + 2, y, CellW - 3, 10);
  end;
  GuiText(GridX - 64, GridY + (NoteHi - NoteLo + 1) * CellH + 4, 'step', 1, 170, 175, 190);

  // mouse
  if GuiInside(GridX, GridY, PageSteps * CellW, (NoteHi - NoteLo + 1) * CellH) then
  begin
    col := Trunc((MouseX - GridX) / CellW);
    row := Trunc((MouseY - GridY) / CellH);
    s := Page * PageSteps + col;
    note := NoteHi - row;
    if s < total then
    begin
      GuiColor(255, 255, 255, 70);
      GuiFrame(GridX + col * CellW, GridY + row * CellH, CellW, CellH);
      GuiText(GridX + PageSteps * CellW - 220, GridY - 14,
              Format('bar %d  step %d  %s', [s div 16 + 1, s mod 16 + 1, NoteName(note)]), 1, 255, 220, 120);
      if MousePressed then
      begin
        if Melody[s] = note then Melody[s] := 0
        else
        begin
          Melody[s] := note;
          PreviewNote(note);
        end;
        Dirty := True;
      end
      else if RightPressed then
      begin
        Melody[s] := -1;
        Dirty := True;
      end;
    end;
  end
  else if GuiInside(GridX, GridY + (NoteHi - NoteLo + 1) * CellH, PageSteps * CellW, 16) and
          (MousePressed or RightPressed) then
  begin
    s := Page * PageSteps + Trunc((MouseX - GridX) / CellW);
    if s < total then
    begin
      if Melody[s] = 0 then Melody[s] := -1
      else if Melody[s] < 0 then Melody[s] := 0;
      Dirty := True;
    end;
  end;
end;

procedure DrawBars;
var
  b, bar, d, q, root: Integer;
  x, y: Single;
begin
  y := GridY + (NoteHi - NoteLo + 1) * CellH + 26;
  for b := 0 to 3 do
  begin
    bar := Page * 4 + b;
    if bar >= Bars then Break;
    x := GridX + b * 16 * CellW + 4;
    GuiText(x, y, 'Bar ' + IntToStr(bar + 1), 1, 255, 210, 80);
    d := GuiSpin(x, y + 14, 228, 'Bass', NoteName(BassRoots[bar]));
    if d <> 0 then
    begin
      if ShiftDown then d := d * 12;
      BassRoots[bar] := EnsureRange(BassRoots[bar] + d, 24, 72);
      for q := 0 to High(Chords[bar]) do Chords[bar][q] := Chords[bar][q] + d;
      PreviewNote(BassRoots[bar] + 12);
      Dirty := True;
    end;
    GuiText(x, y + 46, 'Chord');
    if GuiButton(x + 98, y + 40, 130, 20, ChordName(bar)) then
    begin
      q := ChordQuality(Chords[bar], root);
      q := (q + 1) mod 6;
      SetChord(bar, q);
      PreviewNote(Chords[bar][0] + 12);
      Dirty := True;
    end;
  end;
end;

procedure DrawUI;
var
  n: Integer;
begin
  GuiColor(16, 18, 24);
  GuiFill(0, 0, WinW, WinH);
  GuiText(16, 14, 'MUSIC EDITOR', 2, 255, 210, 80);
  GuiText(230, 20, DataDir + 'music.ini');
  if Dirty then GuiText(WinW - 150, 20, '* not saved', 1, 255, 140, 90);

  if Playing then
  begin
    if GuiButton(16, 50, 110, 40, 'STOP (Space)', True) then TogglePlay;
  end
  else if GuiButton(16, 50, 110, 40, 'PLAY (Space)') then TogglePlay;

  if GuiSlider(140, 52, 230, 'Tempo (BPM)', MusicTempo, 40, 240, 0) then
  begin
    RecalcMusic;
    Dirty := True;
  end;
  if GuiSlider(390, 52, 200, 'Volume', MusicVolume, 0, 2, 2) then Dirty := True;
  if GuiButton(610, 56, 140, 26, 'Music in game', GameMusicOn) then
  begin
    GameMusicOn := not GameMusicOn;
    Dirty := True;
  end;

  n := Bars;
  GuiText(770, 52, Format('Bars %d-%d of %d', [Page * 4 + 1, Min(n, Page * 4 + 4), n]));
  if GuiButton(770, 66, 36, 22, '<') and (Page > 0) then Dec(Page);
  if GuiButton(810, 66, 36, 22, '>') and ((Page + 1) * PageSteps < n * 16) then Inc(Page);
  if GuiButton(856, 66, 70, 22, '+ bar') and (n < 64) then
  begin
    SetLength(Melody, (n + 1) * 16);
    FillChar(Melody[n * 16], 16 * SizeOf(Integer), 0);
    NormaliseSong;
    Dirty := True;
  end;
  if GuiButton(930, 66, 70, 22, '- bar') and (n > 1) then
  begin
    SetLength(Melody, (n - 1) * 16);
    SetLength(BassRoots, n - 1);
    SetLength(Chords, n - 1);
    NormaliseSong;
    Dirty := True;
  end;

  DrawGrid;
  DrawBars;

  GuiText(16, 646, 'Left click: note (again = hold)   Right click: rest   Step lane: hold/rest   Shift: octave on Bass', 1, 170, 175, 190);
  if GuiButton(16, 670, 120, 32, 'Save (F2)') then DoSave;
  if GuiButton(146, 670, 120, 32, 'Reload (F5)') then DoReload;
  if GuiButton(276, 670, 120, 32, 'Defaults') then DoDefaults;
  if GuiButton(406, 670, 140, 32, 'Clear melody') then
  begin
    for n := 0 to High(Melody) do Melody[n] := 0;
    if Length(Melody) > 0 then Melody[0] := -1;
    Dirty := True;
  end;
  if StatusTime > 0 then GuiText(570, 682, Status, 1, 255, 220, 120);
end;

var
  Ev: TSDL_Event;
  Running: Boolean;
  Freq, LastTick, NowTick: UInt64;
  FrameTime: Double;
  sc: TSDL_Scancode;

begin
  Randomize;
  InitCommon;
  LoadAllData(False);
  GameMusicOn := MusicOn;
  MusicOn := False;
  NormaliseSong;

  if not SDL_Init(SDL_INIT_VIDEO) then Halt(1);
  if not SDL_CreateWindowAndRenderer('Pseudo 3D Road - Music editor', WinW, WinH, 0, @Win, @Ren) then
  begin
    SDL_Quit;
    Halt(1);
  end;
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  GuiRen := Ren;

  EngineOn := False;
  InitAudio;
  ResetMusic;

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
        else if sc = SDL_SCANCODE_SPACE then TogglePlay
        else if (sc = SDL_SCANCODE_LEFT) and (Page > 0) then Dec(Page)
        else if (sc = SDL_SCANCODE_RIGHT) and ((Page + 1) * PageSteps < Bars * 16) then Inc(Page)
        else if sc = SDL_SCANCODE_F2 then DoSave
        else if sc = SDL_SCANCODE_F5 then DoReload;
      end;
    end;

    NowTick := SDL_GetPerformanceCounter;
    FrameTime := (NowTick - LastTick) / Freq;
    LastTick := NowTick;
    if StatusTime > 0 then StatusTime := StatusTime - FrameTime;

    // editor plays even if the game is set to muted
    Muted := False;
    FeedAudio(0, False, False);

    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    DrawUI;
    SDL_RenderPresent(Ren);
  end;

  CloseAudio;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
end.
