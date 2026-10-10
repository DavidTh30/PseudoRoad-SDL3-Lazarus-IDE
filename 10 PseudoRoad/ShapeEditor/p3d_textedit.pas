unit p3d_textedit;

{ Pseudo 3D Road - a small text editor drawn with SDL3 for the editors:
  line numbers, cursor, scrolling, comment / command colouring and red
  markers on lines with problems. One TTextEdit per edited file. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, SDL3, p3d_gui;

const
  TE_LineH = 13;
  TE_Gutter = 40;

type
  TTextEdit = record
    Lines: TStringList;
    X, Y, W, H: Single;
    CurRow, CurCol, TopRow, LeftCol: Integer;
    Focus: Boolean;
    Changed: Boolean;            // set on every edit; the program clears it
    Blink: Double;
    WarnRow: array of Boolean;
  end;

procedure TE_Init(var E: TTextEdit; x, y, w, h: Single);
procedure TE_Free(var E: TTextEdit);
procedure TE_LoadFile(var E: TTextEdit; const path: string);
procedure TE_SetWarnings(var E: TTextEdit; warnings: TStrings);
procedure TE_Draw(var E: TTextEdit; dt: Double; mouseAllowed: Boolean);
procedure TE_Key(var E: TTextEdit; sc: TSDL_Scancode);
procedure TE_Text(var E: TTextEdit; const s: string);
procedure TE_DuplicateLine(var E: TTextEdit);
procedure TE_DeleteLine(var E: TTextEdit);
procedure TE_GotoLine(var E: TTextEdit; row: Integer);
function TE_LineOfWarning(const w: string): Integer;

implementation

function VisRows(const E: TTextEdit): Integer;
begin
  Result := Max(1, Trunc(E.H) div TE_LineH);
end;

function VisCols(const E: TTextEdit): Integer;
begin
  Result := Max(8, (Trunc(E.W) - TE_Gutter - 8) div 8);
end;

procedure ClampCursor(var E: TTextEdit);
begin
  if E.Lines.Count = 0 then E.Lines.Add('');
  E.CurRow := EnsureRange(E.CurRow, 0, E.Lines.Count - 1);
  E.CurCol := EnsureRange(E.CurCol, 0, Length(E.Lines[E.CurRow]));
end;

procedure KeepVisible(var E: TTextEdit);
begin
  if E.CurRow < E.TopRow then E.TopRow := E.CurRow;
  if E.CurRow >= E.TopRow + VisRows(E) then E.TopRow := E.CurRow - VisRows(E) + 1;
  if E.CurCol < E.LeftCol then E.LeftCol := Max(0, E.CurCol - 8);
  if E.CurCol >= E.LeftCol + VisCols(E) then E.LeftCol := E.CurCol - VisCols(E) + 8;
  E.TopRow := EnsureRange(E.TopRow, 0, Max(0, E.Lines.Count - 1));
end;

procedure Edited(var E: TTextEdit);
begin
  E.Changed := True;
  E.Blink := 0;
end;

procedure TE_Init(var E: TTextEdit; x, y, w, h: Single);
begin
  E.Lines := TStringList.Create;
  E.Lines.Add('');
  E.X := x; E.Y := y; E.W := w; E.H := h;
  E.CurRow := 0; E.CurCol := 0; E.TopRow := 0; E.LeftCol := 0;
  E.Focus := False;
  E.Changed := False;
  E.Blink := 0;
  E.WarnRow := nil;
end;

procedure TE_Free(var E: TTextEdit);
begin
  FreeAndNil(E.Lines);
end;

procedure TE_LoadFile(var E: TTextEdit; const path: string);
begin
  try
    E.Lines.LoadFromFile(path);
  except
    E.Lines.Clear;
  end;
  if E.Lines.Count = 0 then E.Lines.Add('');
  E.CurRow := 0; E.CurCol := 0; E.TopRow := 0; E.LeftCol := 0;
  E.Changed := True;
end;

function TE_LineOfWarning(const w: string): Integer;
var
  p, n, code: Integer;
begin
  Result := -1;
  if Copy(w, 1, 5) <> 'line ' then Exit;
  p := Pos(':', w);
  if p < 7 then Exit;
  Val(Copy(w, 6, p - 6), n, code);
  if code = 0 then Result := n - 1;
end;

procedure TE_SetWarnings(var E: TTextEdit; warnings: TStrings);
var
  i, r: Integer;
begin
  SetLength(E.WarnRow, E.Lines.Count);
  for i := 0 to High(E.WarnRow) do E.WarnRow[i] := False;
  if warnings = nil then Exit;
  for i := 0 to warnings.Count - 1 do
  begin
    r := TE_LineOfWarning(warnings[i]);
    if (r >= 0) and (r < Length(E.WarnRow)) then E.WarnRow[r] := True;
  end;
end;

procedure TE_GotoLine(var E: TTextEdit; row: Integer);
begin
  E.CurRow := row;
  E.CurCol := 0;
  ClampCursor(E);
  KeepVisible(E);
  E.Focus := True;
end;

procedure TE_Text(var E: TTextEdit; const s: string);
var
  line: string;
begin
  ClampCursor(E);
  line := E.Lines[E.CurRow];
  Insert(s, line, E.CurCol + 1);
  E.Lines[E.CurRow] := line;
  E.CurCol := E.CurCol + Length(s);
  KeepVisible(E);
  Edited(E);
end;

procedure TE_DuplicateLine(var E: TTextEdit);
begin
  ClampCursor(E);
  E.Lines.Insert(E.CurRow + 1, E.Lines[E.CurRow]);
  Inc(E.CurRow);
  KeepVisible(E);
  Edited(E);
end;

procedure TE_DeleteLine(var E: TTextEdit);
begin
  ClampCursor(E);
  if E.Lines.Count > 1 then E.Lines.Delete(E.CurRow) else E.Lines[0] := '';
  ClampCursor(E);
  KeepVisible(E);
  Edited(E);
end;

procedure TE_Key(var E: TTextEdit; sc: TSDL_Scancode);
var
  line: string;
  prevLen: Integer;
begin
  ClampCursor(E);
  line := E.Lines[E.CurRow];
  if sc = SDL_SCANCODE_BACKSPACE then
  begin
    if E.CurCol > 0 then
    begin
      Delete(line, E.CurCol, 1);
      E.Lines[E.CurRow] := line;
      Dec(E.CurCol);
      Edited(E);
    end
    else if E.CurRow > 0 then
    begin
      prevLen := Length(E.Lines[E.CurRow - 1]);
      E.Lines[E.CurRow - 1] := E.Lines[E.CurRow - 1] + line;
      E.Lines.Delete(E.CurRow);
      Dec(E.CurRow);
      E.CurCol := prevLen;
      Edited(E);
    end;
  end
  else if sc = SDL_SCANCODE_DELETE then
  begin
    if E.CurCol < Length(line) then
    begin
      Delete(line, E.CurCol + 1, 1);
      E.Lines[E.CurRow] := line;
      Edited(E);
    end
    else if E.CurRow < E.Lines.Count - 1 then
    begin
      E.Lines[E.CurRow] := line + E.Lines[E.CurRow + 1];
      E.Lines.Delete(E.CurRow + 1);
      Edited(E);
    end;
  end
  else if (sc = SDL_SCANCODE_RETURN) or (sc = SDL_SCANCODE_KP_ENTER) then
  begin
    E.Lines[E.CurRow] := Copy(line, 1, E.CurCol);
    E.Lines.Insert(E.CurRow + 1, Copy(line, E.CurCol + 1, MaxInt));
    Inc(E.CurRow);
    E.CurCol := 0;
    Edited(E);
  end
  else if sc = SDL_SCANCODE_TAB then TE_Text(E, '  ')
  else if sc = SDL_SCANCODE_LEFT then
  begin
    if E.CurCol > 0 then Dec(E.CurCol)
    else if E.CurRow > 0 then
    begin
      Dec(E.CurRow);
      E.CurCol := Length(E.Lines[E.CurRow]);
    end;
  end
  else if sc = SDL_SCANCODE_RIGHT then
  begin
    if E.CurCol < Length(line) then Inc(E.CurCol)
    else if E.CurRow < E.Lines.Count - 1 then
    begin
      Inc(E.CurRow);
      E.CurCol := 0;
    end;
  end
  else if sc = SDL_SCANCODE_UP then Dec(E.CurRow)
  else if sc = SDL_SCANCODE_DOWN then Inc(E.CurRow)
  else if sc = SDL_SCANCODE_HOME then E.CurCol := 0
  else if sc = SDL_SCANCODE_END then E.CurCol := MaxInt
  else if sc = SDL_SCANCODE_PAGEUP then E.CurRow := E.CurRow - VisRows(E)
  else if sc = SDL_SCANCODE_PAGEDOWN then E.CurRow := E.CurRow + VisRows(E);
  ClampCursor(E);
  KeepVisible(E);
  E.Blink := 0;
end;

procedure TE_Draw(var E: TTextEdit; dt: Double; mouseAllowed: Boolean);
var
  r, row, sp: Integer;
  y, cx: Single;
  line, vis, cmdw: string;
begin
  E.Blink := E.Blink + dt;
  GuiColor(20, 23, 30);
  GuiFill(E.X, E.Y, E.W, E.H);
  GuiColor(28, 32, 42);
  GuiFill(E.X, E.Y, TE_Gutter - 4, E.H);

  if mouseAllowed then
  begin
    if GuiInside(E.X, E.Y, E.W, E.H) then
    begin
      if WheelY <> 0 then
        E.TopRow := EnsureRange(E.TopRow - Round(WheelY) * 3, 0, Max(0, E.Lines.Count - 1));
      if MousePressed then
      begin
        E.Focus := True;
        E.CurRow := E.TopRow + Trunc((MouseY - E.Y) / TE_LineH);
        E.CurCol := E.LeftCol + Round((MouseX - E.X - TE_Gutter) / 8);
        ClampCursor(E);
        E.Blink := 0;
      end;
    end
    else if MousePressed then
      E.Focus := False;
  end;

  for r := 0 to VisRows(E) - 1 do
  begin
    row := E.TopRow + r;
    if row >= E.Lines.Count then Break;
    y := E.Y + r * TE_LineH + 2;
    if row = E.CurRow then
    begin
      GuiColor(255, 230, 0, 28);
      GuiFill(E.X + TE_Gutter - 4, y - 2, E.W - TE_Gutter + 4, TE_LineH);
    end;
    if (row < Length(E.WarnRow)) and E.WarnRow[row] then
    begin
      GuiColor(230, 60, 50);
      GuiFill(E.X, y - 2, 4, TE_LineH);
    end;
    GuiText(E.X + 4, y, Format('%3d', [row + 1]), 1, 110, 116, 130);

    line := E.Lines[row];
    vis := Copy(line, E.LeftCol + 1, VisCols(E));
    if (Length(Trim(line)) > 0) and (Trim(line)[1] = '#') then
      GuiText(E.X + TE_Gutter, y, vis, 1, 120, 150, 120)
    else
    begin
      GuiText(E.X + TE_Gutter, y, vis, 1, 225, 228, 235);
      if E.LeftCol = 0 then
      begin
        sp := Pos(' ', line);
        if sp = 0 then cmdw := line else cmdw := Copy(line, 1, sp - 1);
        GuiText(E.X + TE_Gutter, y, cmdw, 1, 255, 200, 90);
      end;
    end;
  end;

  if E.Focus and (Frac(E.Blink) < 0.6) and (E.CurRow >= E.TopRow) and
     (E.CurRow < E.TopRow + VisRows(E)) then
  begin
    cx := E.X + TE_Gutter + (E.CurCol - E.LeftCol) * 8;
    GuiColor(255, 255, 255);
    GuiFill(cx, E.Y + (E.CurRow - E.TopRow) * TE_LineH, 2, TE_LineH);
  end;

  if E.Focus then GuiColor(255, 200, 40) else GuiColor(70, 78, 92);
  GuiFrame(E.X, E.Y, E.W, E.H);
end;

end.
