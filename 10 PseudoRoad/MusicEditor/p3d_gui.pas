unit p3d_gui;

{ Pseudo 3D Road - tiny immediate-mode GUI for the editors:
  text, panels, buttons, sliders and -/+ spinners drawn with SDL3.
  Call GuiBeginFrame before polling events, pass every event to GuiEvent,
  then call the widgets while drawing. Coordinates are window pixels. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, SDL3;

var
  GuiRen: PSDL_Renderer = nil;
  MouseX: Single = 0;
  MouseY: Single = 0;
  MouseDown: Boolean = False;
  MousePressed: Boolean = False;    // left button went down this frame
  MouseReleased: Boolean = False;
  RightPressed: Boolean = False;
  WheelY: Single = 0;
  ShiftDown: Boolean = False;

procedure GuiBeginFrame;
procedure GuiEvent(const ev: TSDL_Event);
procedure GuiColor(r, g, b: Byte; a: Byte = 255);
procedure GuiFill(x, y, w, h: Single);
procedure GuiFrame(x, y, w, h: Single);
procedure GuiText(x, y: Single; const s: string; scale: Single = 1;
                  r: Byte = 230; g: Byte = 230; b: Byte = 230);
function GuiTextWidth(const s: string; scale: Single = 1): Single;
function GuiInside(x, y, w, h: Single): Boolean;
procedure GuiPanel(x, y, w, h: Single; const title: string);
function GuiButton(x, y, w, h: Single; const caption: string; selected: Boolean = False): Boolean;
function GuiSlider(x, y, w: Single; const caption: string; var value: Double;
                   lo, hi: Double; decimals: Integer = 0): Boolean;
function GuiSpin(x, y, w: Single; const caption, valueText: string): Integer;

implementation

var
  GuiId: Integer = 0;
  GuiActive: Integer = 0;

function ClampF(v, lo, hi: Double): Double;
begin
  if v < lo then Result := lo
  else if v > hi then Result := hi
  else Result := v;
end;

function MaxD(a, b: Double): Double;
begin
  if a > b then Result := a else Result := b;
end;

procedure GuiBeginFrame;
begin
  MousePressed := False;
  MouseReleased := False;
  RightPressed := False;
  WheelY := 0;
  GuiId := 0;
  if not MouseDown then GuiActive := 0;
end;

procedure GuiEvent(const ev: TSDL_Event);
begin
  if ev._type = SDL_EVENT_MOUSE_MOTION then
  begin
    MouseX := ev.motion.x;
    MouseY := ev.motion.y;
  end
  else if ev._type = SDL_EVENT_MOUSE_BUTTON_DOWN then
  begin
    MouseX := ev.button.x;
    MouseY := ev.button.y;
    if ev.button.button = SDL_BUTTON_LEFT then
    begin
      MouseDown := True;
      MousePressed := True;
    end
    else if ev.button.button = SDL_BUTTON_RIGHT then
      RightPressed := True;
  end
  else if ev._type = SDL_EVENT_MOUSE_BUTTON_UP then
  begin
    if ev.button.button = SDL_BUTTON_LEFT then
    begin
      MouseDown := False;
      MouseReleased := True;
    end;
  end
  else if ev._type = SDL_EVENT_MOUSE_WHEEL then
    WheelY := WheelY + ev.wheel.y
  else if ev._type = SDL_EVENT_KEY_DOWN then
  begin
    if (ev.key.scancode = SDL_SCANCODE_LSHIFT) or (ev.key.scancode = SDL_SCANCODE_RSHIFT) then
      ShiftDown := True;
  end
  else if ev._type = SDL_EVENT_KEY_UP then
  begin
    if (ev.key.scancode = SDL_SCANCODE_LSHIFT) or (ev.key.scancode = SDL_SCANCODE_RSHIFT) then
      ShiftDown := False;
  end;
end;

procedure GuiColor(r, g, b: Byte; a: Byte = 255);
begin
  SDL_SetRenderDrawColor(GuiRen, r, g, b, a);
end;

procedure GuiFill(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderFillRect(GuiRen, @rc);
end;

procedure GuiFrame(x, y, w, h: Single);
var
  rc: TSDL_FRect;
begin
  rc.x := x; rc.y := y; rc.w := w; rc.h := h;
  SDL_RenderRect(GuiRen, @rc);
end;

procedure GuiText(x, y: Single; const s: string; scale: Single = 1;
                  r: Byte = 230; g: Byte = 230; b: Byte = 230);
begin
  SDL_SetRenderScale(GuiRen, scale, scale);
  SDL_SetRenderDrawColor(GuiRen, r, g, b, 255);
  SDL_RenderDebugText(GuiRen, x / scale, y / scale, PChar(s));
  SDL_SetRenderScale(GuiRen, 1, 1);
end;

function GuiTextWidth(const s: string; scale: Single = 1): Single;
begin
  Result := Length(s) * 8 * scale;
end;

function GuiInside(x, y, w, h: Single): Boolean;
begin
  Result := (MouseX >= x) and (MouseX < x + w) and (MouseY >= y) and (MouseY < y + h);
end;

procedure GuiPanel(x, y, w, h: Single; const title: string);
begin
  GuiColor(22, 26, 34, 235);
  GuiFill(x, y, w, h);
  GuiColor(255, 200, 40);
  GuiFill(x, y, w, 2);
  GuiColor(70, 78, 92);
  GuiFrame(x, y, w, h);
  if title <> '' then GuiText(x + 10, y + 10, title, 1.5, 255, 210, 80);
end;

function GuiButton(x, y, w, h: Single; const caption: string; selected: Boolean = False): Boolean;
var
  hover: Boolean;
begin
  Inc(GuiId);
  hover := GuiInside(x, y, w, h);
  if selected then GuiColor(200, 150, 30)
  else if hover and MouseDown then GuiColor(90, 100, 120)
  else if hover then GuiColor(70, 80, 98)
  else GuiColor(48, 55, 68);
  GuiFill(x, y, w, h);
  GuiColor(100, 110, 130);
  GuiFrame(x, y, w, h);
  GuiText(x + (w - GuiTextWidth(caption)) / 2, y + (h - 8) / 2, caption);
  Result := hover and MousePressed;
end;

function GuiSlider(x, y, w: Single; const caption: string; var value: Double;
                   lo, hi: Double; decimals: Integer = 0): Boolean;
var
  id: Integer;
  old, frac, unitStep, p10: Double;
  txt, fmt: string;
begin
  Inc(GuiId);
  id := GuiId;
  old := value;
  if hi <= lo then hi := lo + 1;
  p10 := Power(10, decimals);
  unitStep := 1 / p10;

  if MousePressed and GuiInside(x, y + 10, w, 20) then GuiActive := id;
  if (GuiActive = id) and MouseDown then
    value := lo + ClampF((MouseX - x) / w, 0, 1) * (hi - lo);
  if (WheelY <> 0) and GuiInside(x, y, w, 30) then
    value := value + WheelY * MaxD(unitStep, (hi - lo) / 100);
  value := ClampF(Round(value * p10) / p10, lo, hi);

  if decimals <= 0 then fmt := '0' else fmt := '0.' + StringOfChar('0', decimals);
  txt := FormatFloat(fmt, value);
  GuiText(x, y, caption);
  GuiText(x + w - GuiTextWidth(txt), y, txt, 1, 255, 220, 120);

  frac := (value - lo) / (hi - lo);
  GuiColor(45, 50, 62);
  GuiFill(x, y + 14, w, 10);
  GuiColor(220, 160, 40);
  GuiFill(x, y + 14, w * frac, 10);
  if GuiActive = id then GuiColor(255, 255, 255) else GuiColor(200, 205, 215);
  GuiFill(x + w * frac - 3, y + 11, 6, 16);

  Result := value <> old;
end;

function GuiSpin(x, y, w: Single; const caption, valueText: string): Integer;
var
  bx: Single;
begin
  Result := 0;
  GuiText(x, y + 6, caption);
  bx := x + w - 130;
  if GuiButton(bx, y, 24, 20, '-') then Result := -1;
  GuiColor(30, 34, 44);
  GuiFill(bx + 26, y, 78, 20);
  GuiText(bx + 26 + (78 - GuiTextWidth(valueText)) / 2, y + 6, valueText, 1, 255, 220, 120);
  if GuiButton(bx + 106, y, 24, 20, '+') then Result := 1;
end;

end.
