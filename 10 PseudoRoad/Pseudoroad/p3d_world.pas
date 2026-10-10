unit p3d_world;

{ Pseudo 3D Road - shared world unit: track building, scenery, traffic,
  vehicle models (data\models\*.car), scenery shapes (data\shapes\*.shape),
  bitmaps (data\bitmaps\*.bmp), the road renderer, mirror and minimap. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, SDL3, p3d_common;

const
  DrawDistance    = 300;
  FogDensity      = 5.0;
  MirrorCamHeight = 1000.0;
  MirrorDistance  = 120;
  MaxDrawFaces    = 200;

  MaxGlows        = 600;
  ColSun:       TRGB = (r: 255; g: 240; b: 180);
  ColMoon:      TRGB = (r: 235; g: 235; b: 215);
  ColRumbleL:   TRGB = (r: 210; g: 30;  b: 30);
  ColRumbleD:   TRGB = (r: 240; g: 240; b: 240);
  ColLane:      TRGB = (r: 220; g: 220; b: 220);
  ColStart:     TRGB = (r: 250; g: 250; b: 250);
  ColFinish:    TRGB = (r: 25;  g: 25;  b: 25);

var
  // current season / time colours (ApplyLook sets them from seasons.ini)
  ColSkyTop:    TRGB = (r: 30;  g: 80;  b: 180);
  ColSkyBottom: TRGB = (r: 165; g: 205; b: 240);
  ColFog:       TRGB = (r: 150; g: 188; b: 215);
  ColMountain:  TRGB = (r: 115; g: 135; b: 180);
  ColHills:     TRGB = (r: 65;  g: 135; b: 80);
  ColGrassL:    TRGB = (r: 16;  g: 170; b: 16);
  ColGrassD:    TRGB = (r: 0;   g: 150; b: 0);
  ColRoadL:     TRGB = (r: 107; g: 107; b: 107);
  ColRoadD:     TRGB = (r: 100; g: 100; b: 100);
  NightMul: Double = 1;          // 1 by day, darker at night
  FlowersOn: Boolean = True;
  ShowWeather: Boolean = True;
  ShapeHighlightLine: Integer = -1;  // shape editor: commands from this line glow yellow

type
  TV3 = record
    x, y, z: Double;
  end;
  TQuad = array[0..3] of TV3;

  TColSpec = record
    body: Boolean;               // use the vehicle's paint
    k: Double;                   // shade factor for the paint
    rgb: TRGB;                   // fixed colour (already shaded)
  end;

  TModelFace = record
    p: TQuad;
    n: TV3;
    col: TColSpec;
    decals: TIntArray;
    line: Integer;               // line in the .car file (for editors)
  end;

  TModelDecal = record
    p: TQuad;
    col: TColSpec;
    glow: Boolean;
    line: Integer;
  end;

  TModel = record
    key, name: string;
    length, width, height, speed, hit: Double;
    palette: TRGBArray;
    faces: array of TModelFace;
    decals: array of TModelDecal;
  end;

  TShapeCmdKind = (scRect, scEllipse, scPoly, scImage, scGlow);

  TShapeCmd = record
    kind: TShapeCmdKind;
    flower: Boolean;
    rgb: TRGB;
    v: array[0..15] of Double;
    n: Integer;                  // points of a poly
    img: string;
    line: Integer;               // line in the .shape file (for editors)
  end;

  TShape = record
    width, height, shadow: Double;
    solid: Boolean;
    lod: TRGB;
    mirror: Integer;             // 0 none, 1 by sign of variant, 2 by road side
    variants: Integer;
    cmds: array of TShapeCmd;
  end;
  PShape = ^TShape;

  TProj = record
    wx, wy, wz: Double;
    cx, cy, cz: Double;
    sx, sy, sw, scale: Double;
  end;

  TSpriteKind = (skPine, skTree, skBush, skFlowerBush, skBillboard, skPole,
                 skChevron, skWarning);

  TSprite = record
    kind: TSpriteKind;
    offset: Double;
    variant: Integer;
  end;

  TSegment = record
    index: Integer;
    p1, p2: TProj;
    curve: Double;
    dark: Boolean;
    special: Integer;            // 0 normal, 1 start line, 2 finish
    sprites: array of TSprite;
    clip, fog: Double;
  end;
  PSegment = ^TSegment;

  TCar = record
    z, offset, speed: Double;
    cruise, brake, look, yaw: Double;
    color: TRGB;
    m: Integer;                  // model index
    w: Double;                   // width in road units (road edge = 1)
    hit: Double;                 // collision length
  end;
  PCar = ^TCar;

  THook = procedure;

const
  ShapeFile: array[TSpriteKind] of string = (
    'pine', 'tree', 'bush', 'flowerbush', 'billboard', 'lamp', 'chevron', 'warning');

var
  Ren: PSDL_Renderer = nil;

  Segments: array of TSegment;
  SectionStarts: TIntArray;      // first segment of every track section
  TrackLength: Double = 0;
  StartIdx: Integer = 0;

  Cars: array of TCar;
  Models: array of TModel;
  TypeModel: TIntArray;          // model of every entry in TrafficTypes
  PlayerModel: Integer = 0;
  Shapes: array[TSpriteKind] of TShape;

  CameraDepth: Double = 0.84;    // default (fov 100) projection depth
  PlayerZ: Double = 839;         // car position ahead of the physics "Position"
  ViewDepth: Double = 0.84;
  ViewCX: Double = ScreenW / 2;
  ViewCY: Double = ScreenH / 2;
  SkyOffset: Double = 0;
  HillOffset: Double = 0;

  PlayerSX: Double = ScreenW / 2;   // player car on screen (set by RenderWorld)
  PlayerBY: Double = ScreenH - 40;
  PlayerU: Double = 0.43;

  BeforePlayerHook: THook = nil;    // e.g. dust behind the car
  AfterPlayerHook: THook = nil;     // e.g. sparks in front of the car

  MapNX, MapNY: TNumArray;          // minimap points, 0..1
  HighlightLine: Integer = -1;      // model editor: faces from this file line glow yellow

procedure InitWorld;
procedure ReloadWorldGraphics;     // models, shapes, bitmaps

function Increase(start, inc, mx: Double): Double;
function PercentRemaining(n, total: Double): Double;
function WrapDist(d: Double): Double;
function Overlap(x1, w1, x2, w2, pct: Double): Boolean;
function Fogged(const c: TRGB; fog: Double): TRGB;
function FoggedLit(const c: TRGB; fog: Double): TRGB;

procedure SetCol(const c: TRGB; a: Byte = 255);
procedure FillR(x, y, w, h: Double);
procedure FillPoly(xl1, xr1, y1, xl2, xr2, y2, clipY: Double);
procedure FillConvex(const px, py: array of Double; n: Integer);
procedure FillEllipse(cx, cy, rx, ry: Double);
function BeginClip(clip: Double): Boolean;
procedure EndClip;
procedure DrawText(x, y: Single; const s: string; scale: Single = 2);

function FindSegment(z: Double): Integer;
function RoadHeightAt(z: Double): Double;
function BuildTrack(const secs: TTrackSections; seed: LongInt): Boolean;
procedure BuildTrackFromFile(seed: LongInt);
procedure ResetTraffic(maxSpeed: Double);

procedure LoadModels;
function FindModel(const key: string): Integer;
function LoadModelLines(L: TStrings; const key: string; out M: TModel; warnings: TStrings): Boolean;
function LoadModelFile(const path, key: string; out M: TModel): Boolean;
procedure LoadShapes;
function LoadShapeLines(L: TStrings; out S: TShape; warnings: TStrings): Boolean;
function LoadShapeFile(const path: string; out S: TShape): Boolean;
procedure ApplyLook;                                  // colours of the current season / time
procedure SetLook(season: Integer; night: Boolean);   // switch season / time and reload shapes
function SpriteWidth(kind: TSpriteKind): Double;
function IsSolid(kind: TSpriteKind): Boolean;
procedure FreeTextures;

procedure ApplyCameraView(const c: TCamera);
procedure Project(var p: TProj; camX, camY, camZ: Double; back: Boolean = False);
procedure DrawBackground(playerY: Double);
procedure DrawRoadQuad(const nearP, farP: TProj; dark: Boolean; special: Integer; fog, clip: Double);
procedure DrawCar(const M: TModel; cx, by, u: Double; const paint: TRGB; fog, yaw, clip: Double;
                  front: Boolean = False);
procedure DrawCarAngle(const M: TModel; cx, by, u: Double; const paint: TRGB; fog, angle, clip: Double);
procedure DrawSprite(const sp: TSprite; sx, sy, u, clip, fog: Double);
procedure DrawShapeAt(const S: TShape; const sp: TSprite; sx, sy, u, clip, fog: Double);
procedure BeginGlows;
procedure FlushGlows;
procedure DrawWeather;

procedure RenderWorld(const c: TCamera; carZ, playerX: Double; showPlayer: Boolean;
                      const playerPaint: TRGB; steer, bounce: Double);
procedure RenderMirror(tex: PSDL_Texture; carZ, playerX: Double);

procedure BuildMinimap;
procedure DrawMinimap(x, y, size: Single; carZ: Double; showCars: Boolean;
                      hiFrom, hiTo: Integer; bgAlpha: Byte = 130);

implementation

var
  TexNames: TStringList = nil;
  TexList: array of PSDL_Texture;
  GlowX, GlowY, GlowR, GlowClip: array[0..MaxGlows - 1] of Double;
  GlowC: array[0..MaxGlows - 1] of TRGB;
  GlowN: Integer = 0;
  RndA, RndB, RndC: array[0..999] of Double;   // fixed random numbers: stars, weather

{ ---------------------------------------------------------------- basics }

procedure InitWorld;
var
  i: Integer;
  seed: LongWord;

  {$PUSH}{$Q-}{$R-}   // the generator relies on wrap-around arithmetic
  function NextRnd: Double;
  begin
    seed := seed * 1664525 + 1013904223;
    Result := (seed shr 8) / 16777216;
  end;
  {$POP}

begin
  seed := 20261011;
  for i := 0 to 999 do
  begin
    RndA[i] := NextRnd;
    RndB[i] := NextRnd;
    RndC[i] := NextRnd;
  end;
  CameraDepth := 1 / Tan((DefFOV / 2) * Pi / 180);
  PlayerZ := DefCamHeight * CameraDepth;
  ViewDepth := CameraDepth;
  ViewCX := ScreenW / 2;
  ViewCY := ScreenH / 2;
  if TexNames = nil then TexNames := TStringList.Create;
end;

function Increase(start, inc, mx: Double): Double;
begin
  Result := start + inc;
  if mx <= 0 then Exit;
  while Result >= mx do Result := Result - mx;
  while Result < 0 do Result := Result + mx;
end;

function PercentRemaining(n, total: Double): Double;
begin
  Result := (n - Floor(n / total) * total) / total;
end;

function WrapDist(d: Double): Double;
begin
  if d < -TrackLength / 2 then Result := d + TrackLength
  else if d > TrackLength / 2 then Result := d - TrackLength
  else Result := d;
end;

function Overlap(x1, w1, x2, w2, pct: Double): Boolean;
var
  half: Double;
begin
  half := pct / 2;
  Result := not ((x1 + w1 * half < x2 - w2 * half) or
                 (x1 - w1 * half > x2 + w2 * half));
end;

function Fogged(const c: TRGB; fog: Double): TRGB;
begin
  if NightMul < 0.999 then Result := Mix(ColFog, Shade(c, NightMul), fog)
  else Result := Mix(ColFog, c, fog);
end;

{ lights are not darkened at night }
function FoggedLit(const c: TRGB; fog: Double): TRGB;
begin
  Result := Mix(ColFog, c, fog);
end;

procedure SetCol(const c: TRGB; a: Byte = 255);
begin
  SDL_SetRenderDrawColor(Ren, c.r, c.g, c.b, a);
end;

procedure FillR(x, y, w, h: Double);
var
  r: TSDL_FRect;
begin
  r.x := x; r.y := y; r.w := w; r.h := h;
  SDL_RenderFillRect(Ren, @r);
end;

procedure FillPoly(xl1, xr1, y1, xl2, xr2, y2, clipY: Double);
var
  ya, yb, t, xl, xr, dy: Double;
  iy, iyStart, iyEnd: Integer;
  r: TSDL_FRect;
begin
  dy := y1 - y2;
  if dy <= 0 then Exit;
  ya := MaxD(y2, 0);
  yb := MinD(MinD(y1, clipY), ScreenH);
  if yb <= ya then Exit;
  iyStart := Ceil(ya - 0.5);
  iyEnd := Ceil(yb - 0.5) - 1;
  for iy := iyStart to iyEnd do
  begin
    t := (iy + 0.5 - y2) / dy;
    xl := MaxD(xl2 + (xl1 - xl2) * t, -1);
    xr := MinD(xr2 + (xr1 - xr2) * t, ScreenW + 1);
    if xr > xl then
    begin
      r.x := xl; r.y := iy; r.w := xr - xl; r.h := 1;
      SDL_RenderFillRect(Ren, @r);
    end;
  end;
end;

procedure FillConvex(const px, py: array of Double; n: Integer);
var
  i, j, iy, iyStart, iyEnd: Integer;
  ymin, ymax, yc, xa, xb, x, t: Double;
begin
  if n < 3 then Exit;
  ymin := py[0]; ymax := py[0];
  for i := 1 to n - 1 do
  begin
    ymin := MinD(ymin, py[i]);
    ymax := MaxD(ymax, py[i]);
  end;
  ymin := MaxD(ymin, 0);
  ymax := MinD(ymax, ScreenH);
  if ymax <= ymin then Exit;
  iyStart := Ceil(ymin - 0.5);
  iyEnd := Ceil(ymax - 0.5) - 1;
  for iy := iyStart to iyEnd do
  begin
    yc := iy + 0.5;
    xa := 1e30; xb := -1e30;
    for i := 0 to n - 1 do
    begin
      j := (i + 1) mod n;
      if ((py[i] <= yc) and (py[j] > yc)) or ((py[j] <= yc) and (py[i] > yc)) then
      begin
        t := (yc - py[i]) / (py[j] - py[i]);
        x := px[i] + t * (px[j] - px[i]);
        xa := MinD(xa, x);
        xb := MaxD(xb, x);
      end;
    end;
    xa := MaxD(xa, -1);
    xb := MinD(xb, ScreenW + 1);
    if xb > xa then FillR(xa, iy, xb - xa, 1);
  end;
end;

procedure FillEllipse(cx, cy, rx, ry: Double);
var
  iy, y0, y1: Integer;
  dy, hw: Double;
begin
  if (rx <= 0) or (ry <= 0) then Exit;
  if (cy - ry > ScreenH) or (cy + ry < 0) then Exit;
  if ry < 0.75 then
  begin
    FillR(cx - rx, cy - 0.5, 2 * rx, 1);
    Exit;
  end;
  y0 := Floor(MaxD(cy - ry, 0));
  y1 := Ceil(MinD(cy + ry, ScreenH - 1));
  for iy := y0 to y1 do
  begin
    dy := (iy + 0.5 - cy) / ry;
    if Abs(dy) >= 1 then Continue;
    hw := rx * Sqrt(1 - dy * dy);
    FillR(cx - hw, iy, 2 * hw, 1);
  end;
end;

function BeginClip(clip: Double): Boolean;
var
  r: TSDL_Rect;
begin
  if clip >= ScreenH then
  begin
    SDL_SetRenderClipRect(Ren, nil);
    Exit(True);
  end;
  if clip < 1 then Exit(False);
  r.x := 0; r.y := 0; r.w := ScreenW; r.h := Trunc(clip);
  SDL_SetRenderClipRect(Ren, @r);
  Result := True;
end;

procedure EndClip;
begin
  SDL_SetRenderClipRect(Ren, nil);
end;

{ ------------------------------------------------------------- night lights }

procedure BeginGlows;
begin
  GlowN := 0;
end;

procedure AddGlow(x, y, r: Double; const c: TRGB; clip: Double);
begin
  if (GlowN >= MaxGlows) or (r < 0.5) or (y > clip) then Exit;
  GlowX[GlowN] := x;
  GlowY[GlowN] := y;
  GlowR[GlowN] := MinD(r, 260);
  GlowClip[GlowN] := clip;
  GlowC[GlowN] := c;
  Inc(GlowN);
end;

{ soft light blobs, added on top of the darkened scene }
procedure FlushGlows;
var
  i: Integer;
begin
  if GlowN = 0 then Exit;
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_ADD);
  for i := 0 to GlowN - 1 do
  begin
    SetCol(GlowC[i], 26);
    FillEllipse(GlowX[i], GlowY[i], GlowR[i], GlowR[i]);
    SetCol(GlowC[i], 45);
    FillEllipse(GlowX[i], GlowY[i], GlowR[i] * 0.55, GlowR[i] * 0.55);
    SetCol(GlowC[i], 90);
    FillEllipse(GlowX[i], GlowY[i], GlowR[i] * 0.22, GlowR[i] * 0.22);
  end;
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  GlowN := 0;
end;

{ falling snow, leaves, petals or rain in front of everything }
procedure DrawWeather;
var
  lk: TLook;
  i, n: Integer;
  t, x, y, k, sz: Double;
  c: TRGB;
begin
  if not ShowWeather then Exit;
  lk := CurLook;
  if lk.weather = wxNone then Exit;
  n := Min(lk.weatherAmount, 1000);
  t := SDL_GetTicks / 1000;
  k := 0.55 + 0.45 * NightMul;
  for i := 0 to n - 1 do
  begin
    case lk.weather of
      wxSnow:
        begin
          x := WrapUnit(RndA[i] + 0.02 * Sin(t * 0.8 + i) + t * 0.01) * ScreenW;
          y := WrapUnit(RndB[i] + t * (0.05 + 0.06 * RndC[i])) * ScreenH;
          sz := 2 + 3 * RndC[i];
          SetCol(Shade(MakeRGB(250, 250, 255), k), 220);
          FillR(x, y, sz, sz);
        end;
      wxRain:
        begin
          x := WrapUnit(RndA[i] + t * 0.12) * ScreenW;
          y := WrapUnit(RndB[i] + t * (0.9 + 0.4 * RndC[i])) * ScreenH;
          SetCol(Shade(MakeRGB(170, 190, 230), k), 150);
          SDL_RenderLine(Ren, x, y, x - 4, y + 16);
        end;
      wxLeaves, wxPetals:
        begin
          x := WrapUnit(RndA[i] + 0.04 * Sin(t * 1.3 + i * 1.7) + t * 0.03) * ScreenW;
          y := WrapUnit(RndB[i] + t * (0.07 + 0.06 * RndC[i])) * ScreenH;
          if lk.weather = wxLeaves then
          begin
            case i mod 3 of
              0: c := MakeRGB(210, 110, 30);
              1: c := MakeRGB(190, 60, 30);
            else
              c := MakeRGB(220, 170, 40);
            end;
          end
          else if i mod 2 = 0 then c := MakeRGB(250, 190, 210)
          else c := MakeRGB(255, 228, 236);
          SetCol(Shade(c, k), 230);
          sz := 2 + 4 * Abs(Sin(t * 3 + i));
          FillR(x, y, sz, 3);
        end;
    end;
  end;
end;

procedure DrawText(x, y: Single; const s: string; scale: Single = 2);
begin
  SDL_SetRenderScale(Ren, scale, scale);
  SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
  SDL_RenderDebugText(Ren, x + 1, y + 1, PChar(s));
  SDL_SetRenderDrawColor(Ren, 255, 255, 255, 255);
  SDL_RenderDebugText(Ren, x, y, PChar(s));
  SDL_SetRenderScale(Ren, 1, 1);
end;

{ ------------------------------------------------------------ vectors }

function V3(x, y, z: Double): TV3;
begin
  Result.x := x; Result.y := y; Result.z := z;
end;

function VSub(const a, b: TV3): TV3;
begin
  Result.x := a.x - b.x; Result.y := a.y - b.y; Result.z := a.z - b.z;
end;

function VDot(const a, b: TV3): Double;
begin
  Result := a.x * b.x + a.y * b.y + a.z * b.z;
end;

function VCross(const a, b: TV3): TV3;
begin
  Result.x := a.y * b.z - a.z * b.y;
  Result.y := a.z * b.x - a.x * b.z;
  Result.z := a.x * b.y - a.y * b.x;
end;

function VNorm(const a: TV3; out ok: Boolean): TV3;
var
  l: Double;
begin
  l := Sqrt(VDot(a, a));
  ok := l > 1e-9;
  if ok then Result := V3(a.x / l, a.y / l, a.z / l) else Result := V3(0, 0, 0);
end;

function VNeg(const a: TV3): TV3;
begin
  Result := V3(-a.x, -a.y, -a.z);
end;

function QuadCenter(const p: array of TV3): TV3;
var
  i: Integer;
begin
  Result := V3(0, 0, 0);
  for i := 0 to 3 do
  begin
    Result.x := Result.x + p[i].x / 4;
    Result.y := Result.y + p[i].y / 4;
    Result.z := Result.z + p[i].z / 4;
  end;
end;

function QuadNormal(const p: array of TV3; out ok: Boolean): TV3;
begin
  Result := VNorm(VCross(VSub(p[1], p[0]), VSub(p[3], p[0])), ok);
  if not ok then
    Result := VNorm(VCross(VSub(p[2], p[1]), VSub(p[3], p[1])), ok);
end;

{ ------------------------------------------------------- vehicle models }

const
  HexFaces: array[0..5, 0..3] of Integer = (
    (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (3, 2, 6, 7), (0, 3, 7, 4), (1, 5, 6, 2));

function LoadModelLines(L: TStrings; const key: string; out M: TModel; warnings: TStrings): Boolean;
var
  named: TStringList;
  t: TStringArray;
  i, j, k, nf, nd, fi: Integer;
  cmd, pl: string;
  standalone: TIntArray;
  v: array[0..7] of TV3;
  q: TQuad;
  cs: TColSpec;
  glow, ok, found: Boolean;
  mc, c, nn: TV3;
  ppos, a0, b0, a1, b1, maxX, maxY, maxZ: Double;
  mn, mx: TV3;
  curLine: Integer;

  function N(idx: Integer): Double;
  begin
    if idx < Length(t) then Result := StrToFloatDef(t[idx], 0, FS) else Result := 0;
  end;

  function ColTok(const tok: string): TColSpec;
  var
    base: string;
    p: Integer;
    rgb: TRGB;
  begin
    base := tok;
    Result.k := 1;
    p := Pos('*', tok);
    if p > 0 then
    begin
      base := Copy(tok, 1, p - 1);
      Result.k := StrToFloatDef(Copy(tok, p + 1, MaxInt), 1, FS);
    end;
    Result.body := SameText(base, 'body');
    rgb := MakeRGB(128, 128, 128);
    if not Result.body then
    begin
      if Pos(',', base) > 0 then rgb := ParseColor(base, rgb)
      else if named.IndexOfName(LowerCase(base)) >= 0 then
        rgb := ParseColor(named.Values[LowerCase(base)], rgb)
      else
        FindNamedColor(base, rgb);
    end;
    Result.rgb := Shade(rgb, Result.k);
  end;

  procedure AddFace(const p: array of TV3; const col: TColSpec; const center: TV3;
                    orient: Boolean);
  var
    nrm, cc: TV3;
    good: Boolean;
    s: Integer;
  begin
    nrm := QuadNormal(p, good);
    if not good then Exit;
    cc := QuadCenter(p);
    if orient and (VDot(nrm, VSub(cc, center)) < 0) then nrm := VNeg(nrm);
    s := Length(M.faces);
    SetLength(M.faces, s + 1);
    M.faces[s].p[0] := p[0]; M.faces[s].p[1] := p[1];
    M.faces[s].p[2] := p[2]; M.faces[s].p[3] := p[3];
    M.faces[s].n := nrm;
    M.faces[s].col := col;
    M.faces[s].decals := nil;
    M.faces[s].line := curLine;
    if not orient then
    begin
      SetLength(standalone, Length(standalone) + 1);
      standalone[High(standalone)] := s;
    end;
  end;

  procedure AddHex(const col: TColSpec);
  var
    hc: TV3;
    f, w: Integer;
  begin
    hc := V3(0, 0, 0);
    for w := 0 to 7 do
    begin
      hc.x := hc.x + v[w].x / 8;
      hc.y := hc.y + v[w].y / 8;
      hc.z := hc.z + v[w].z / 8;
    end;
    for f := 0 to 5 do
      AddFace([v[HexFaces[f, 0]], v[HexFaces[f, 1]], v[HexFaces[f, 2]], v[HexFaces[f, 3]]],
              col, hc, True);
  end;

  procedure AddDecal(const col: TColSpec; isGlow: Boolean);
  var
    s: Integer;
  begin
    s := Length(M.decals);
    SetLength(M.decals, s + 1);
    M.decals[s].p[0] := q[0]; M.decals[s].p[1] := q[1];
    M.decals[s].p[2] := q[2]; M.decals[s].p[3] := q[3];
    M.decals[s].col := col;
    M.decals[s].glow := isGlow;
    M.decals[s].line := curLine;
  end;

  procedure Warn(const msg: string);
  begin
    if warnings <> nil then warnings.Add(Format('line %d: %s', [curLine + 1, msg]));
  end;

begin
  Result := False;
  M.key := key;
  M.name := key;
  M.length := 0; M.width := 0; M.height := 0; M.speed := 1; M.hit := 0;
  M.palette := nil;
  M.faces := nil;
  M.decals := nil;
  standalone := nil;
  curLine := 0;

  named := TStringList.Create;
  try
    for i := 0 to L.Count - 1 do
    begin
      curLine := i;
      t := SplitBy(L[i], ' ');
      if Length(t) = 0 then Continue;
      cmd := LowerCase(t[0]);
      if (cmd[1] = '#') or (cmd[1] = ';') then Continue;

      if cmd = 'name' then
      begin
        M.name := '';
        for j := 1 to High(t) do
        begin
          if j > 1 then M.name := M.name + ' ';
          M.name := M.name + t[j];
        end;
      end
      else if cmd = 'length' then M.length := N(1)
      else if cmd = 'width' then M.width := N(1)
      else if cmd = 'speed' then M.speed := ClampD(N(1), 0.1, 3)
      else if cmd = 'hit' then M.hit := N(1)
      else if cmd = 'colors' then
      begin
        SetLength(M.palette, Length(t) - 1);
        for j := 1 to High(t) do
          M.palette[j - 1] := ParseColor(t[j], MakeRGB(200, 200, 200));
      end
      else if (cmd = 'color') and (Length(t) >= 3) then
        named.Values[LowerCase(t[1])] := t[2]
      else if (cmd = 'box') and (Length(t) >= 8) then
      begin
        v[0] := V3(N(2), N(4), N(6)); v[1] := V3(N(3), N(4), N(6));
        v[2] := V3(N(3), N(4), N(7)); v[3] := V3(N(2), N(4), N(7));
        v[4] := V3(N(2), N(5), N(6)); v[5] := V3(N(3), N(5), N(6));
        v[6] := V3(N(3), N(5), N(7)); v[7] := V3(N(2), N(5), N(7));
        AddHex(ColTok(t[1]));
      end
      else if (cmd = 'hex') and (Length(t) >= 26) then
      begin
        for j := 0 to 7 do v[j] := V3(N(2 + 3 * j), N(3 + 3 * j), N(4 + 3 * j));
        AddHex(ColTok(t[1]));
      end
      else if (cmd = 'face') and (Length(t) >= 14) then
      begin
        for j := 0 to 3 do q[j] := V3(N(2 + 3 * j), N(3 + 3 * j), N(4 + 3 * j));
        AddFace(q, ColTok(t[1]), V3(0, 0, 0), False);
      end
      else if (cmd = 'decal') or (cmd = 'rdecal') then
      begin
        if Length(t) < 3 then
        begin
          Warn('a decal needs a colour and its corners');
          Continue;
        end;
        k := 2;
        glow := SameText(t[2], 'glow');
        if glow then k := 3;
        cs := ColTok(t[1]);
        if cmd = 'decal' then
        begin
          if Length(t) < k + 12 then
          begin
            Warn('decal needs 4 corners (12 numbers)');
            Continue;
          end;
          for j := 0 to 3 do q[j] := V3(N(k + 3 * j), N(k + 1 + 3 * j), N(k + 2 + 3 * j));
        end
        else
        begin
          if Length(t) < k + 6 then
          begin
            Warn('rdecal needs a plane (x, y or z), a position and 4 numbers');
            Continue;
          end;
          pl := LowerCase(t[k]);
          ppos := N(k + 1);
          a0 := N(k + 2); b0 := N(k + 3); a1 := N(k + 4); b1 := N(k + 5);
          if pl = 'z' then
          begin
            q[0] := V3(a0, b0, ppos); q[1] := V3(a1, b0, ppos);
            q[2] := V3(a1, b1, ppos); q[3] := V3(a0, b1, ppos);
          end
          else if pl = 'x' then
          begin
            q[0] := V3(ppos, b0, a0); q[1] := V3(ppos, b0, a1);
            q[2] := V3(ppos, b1, a1); q[3] := V3(ppos, b1, a0);
          end
          else
          begin
            q[0] := V3(a0, ppos, b0); q[1] := V3(a1, ppos, b0);
            q[2] := V3(a1, ppos, b1); q[3] := V3(a0, ppos, b1);
          end;
        end;
        AddDecal(cs, glow);
      end
      else if (cmd = 'box') or (cmd = 'hex') or (cmd = 'face') or (cmd = 'color') then
        Warn('not enough numbers for "' + cmd + '"')
      else
        Warn('unknown command "' + t[0] + '"');
    end;
  finally
    named.Free;
  end;

  nf := Length(M.faces);
  if nf = 0 then
  begin
    if warnings <> nil then warnings.Add('no faces yet - add box, hex or face lines');
    Exit;
  end;

  // measure the model
  maxX := 0; maxY := 0; maxZ := 0;
  for i := 0 to nf - 1 do
    for j := 0 to 3 do
    begin
      maxX := MaxD(maxX, Abs(M.faces[i].p[j].x));
      maxY := MaxD(maxY, M.faces[i].p[j].y);
      maxZ := MaxD(maxZ, M.faces[i].p[j].z);
    end;
  M.height := maxY;
  if M.length <= 0 then M.length := maxZ;
  if M.width <= 0 then M.width := 2 * maxX;
  if M.hit <= 0 then M.hit := M.length * 0.38;
  mc := V3(0, M.height / 2, M.length / 2);

  // single faces point away from the middle of the model
  for i := 0 to High(standalone) do
  begin
    fi := standalone[i];
    c := QuadCenter(M.faces[fi].p);
    if VDot(M.faces[fi].n, VSub(c, mc)) < 0 then M.faces[fi].n := VNeg(M.faces[fi].n);
  end;

  // every decal belongs to the face it lies on
  nd := Length(M.decals);
  for i := 0 to nd - 1 do
  begin
    nn := QuadNormal(M.decals[i].p, ok);
    if not ok then Continue;
    c := QuadCenter(M.decals[i].p);
    if VDot(nn, VSub(c, mc)) < 0 then nn := VNeg(nn);
    found := False;
    for fi := 0 to nf - 1 do
    begin
      if VDot(M.faces[fi].n, nn) < 0.98 then Continue;
      if Abs(VDot(M.faces[fi].n, VSub(c, M.faces[fi].p[0]))) > 3 then Continue;
      mn := M.faces[fi].p[0]; mx := M.faces[fi].p[0];
      for j := 1 to 3 do
      begin
        mn.x := MinD(mn.x, M.faces[fi].p[j].x); mx.x := MaxD(mx.x, M.faces[fi].p[j].x);
        mn.y := MinD(mn.y, M.faces[fi].p[j].y); mx.y := MaxD(mx.y, M.faces[fi].p[j].y);
        mn.z := MinD(mn.z, M.faces[fi].p[j].z); mx.z := MaxD(mx.z, M.faces[fi].p[j].z);
      end;
      if (c.x < mn.x - 3) or (c.x > mx.x + 3) or (c.y < mn.y - 3) or (c.y > mx.y + 3) or
         (c.z < mn.z - 3) or (c.z > mx.z + 3) then Continue;
      k := Length(M.faces[fi].decals);
      SetLength(M.faces[fi].decals, k + 1);
      M.faces[fi].decals[k] := i;
      found := True;
      Break;
    end;
    if not found then
    begin
      // no face under it: draw it as a face of its own
      curLine := M.decals[i].line;
      Warn('decal does not lie on any face - drawn on its own');
      k := Length(M.faces);
      SetLength(M.faces, k + 1);
      M.faces[k].p := M.decals[i].p;
      M.faces[k].n := nn;
      M.faces[k].col := M.decals[i].col;
      M.faces[k].decals := nil;
      M.faces[k].line := M.decals[i].line;
    end;
  end;
  Result := True;
end;

function LoadModelFile(const path, key: string; out M: TModel): Boolean;
var
  L: TStringList;
begin
  Result := False;
  M.key := key; M.name := key;
  M.faces := nil; M.decals := nil; M.palette := nil;
  M.length := 850; M.width := 640; M.height := 300; M.speed := 1; M.hit := 320;
  if not FileExists(path) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(path);
    except
      Exit;
    end;
    Result := LoadModelLines(L, key, M, nil);
  finally
    L.Free;
  end;
end;

procedure FallbackModel(const key: string; out M: TModel);
var
  cs: TColSpec;
  hc: TV3;
  v: array[0..7] of TV3;
  f, s: Integer;
  good: Boolean;
  q: TQuad;
begin
  M.key := key; M.name := key;
  M.length := 850; M.width := 640; M.height := 300; M.speed := 1; M.hit := 320;
  M.palette := nil; M.faces := nil; M.decals := nil;
  cs.body := True; cs.k := 1; cs.rgb := MakeRGB(128, 128, 128);
  v[0] := V3(-320, 0, 0);  v[1] := V3(320, 0, 0);  v[2] := V3(320, 0, 850);  v[3] := V3(-320, 0, 850);
  v[4] := V3(-320, 300, 0); v[5] := V3(320, 300, 0); v[6] := V3(320, 300, 850); v[7] := V3(-320, 300, 850);
  hc := V3(0, 150, 425);
  for f := 0 to 5 do
  begin
    q[0] := v[HexFaces[f, 0]]; q[1] := v[HexFaces[f, 1]];
    q[2] := v[HexFaces[f, 2]]; q[3] := v[HexFaces[f, 3]];
    s := Length(M.faces);
    SetLength(M.faces, s + 1);
    M.faces[s].p := q;
    M.faces[s].n := QuadNormal(q, good);
    if VDot(M.faces[s].n, VSub(QuadCenter(q), hc)) < 0 then M.faces[s].n := VNeg(M.faces[s].n);
    M.faces[s].col := cs;
    M.faces[s].decals := nil;
    M.faces[s].line := -1;
  end;
end;

function FindModel(const key: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Models) do
    if SameText(Models[i].key, key) then Exit(i);
  Result := 0;
end;

function AddModel(const key: string): Integer;
var
  i: Integer;
  M: TModel;
begin
  for i := 0 to High(Models) do
    if SameText(Models[i].key, key) then Exit(i);
  if not LoadModelFile(ModelPath(key), key, M) then
    if not LoadModelFile(ModelPath('sedan'), key, M) then
      FallbackModel(key, M);
  Result := Length(Models);
  SetLength(Models, Result + 1);
  Models[Result] := M;
end;

procedure LoadModels;
var
  i: Integer;
begin
  Models := nil;
  PlayerModel := AddModel(PlayerModelName);
  SetLength(TypeModel, Length(TrafficTypes));
  for i := 0 to High(TrafficTypes) do
    TypeModel[i] := AddModel(TrafficTypes[i].name);
end;

{ ------------------------------------------------------ scenery shapes }

function LoadShapeLines(L: TStrings; out S: TShape; warnings: TStrings): Boolean;
var
  t: TStringArray;
  i, j, n: Integer;
  cmd, m: string;
  c: TShapeCmd;

  function N_(idx: Integer): Double;
  begin
    if idx < Length(t) then Result := StrToFloatDef(t[idx], 0, FS) else Result := 0;
  end;

  procedure SetColor(const tok: string);
  var
    rgb: TRGB;
  begin
    c.flower := SameText(tok, '$flower');
    rgb := MakeRGB(128, 128, 128);
    if c.flower then
      rgb := MakeRGB(255, 255, 255)
    else if (Length(tok) > 1) and (tok[1] = '$') then
      FindNamedColor(Copy(tok, 2, MaxInt), rgb)
    else
      rgb := ParseColor(tok, rgb);
    c.rgb := rgb;
  end;

  procedure Push;
  var
    k: Integer;
  begin
    k := Length(S.cmds);
    SetLength(S.cmds, k + 1);
    S.cmds[k] := c;
  end;

  procedure Warn(const msg: string);
  begin
    if warnings <> nil then warnings.Add(Format('line %d: %s', [i + 1, msg]));
  end;

begin
  Result := False;
  S.width := 1000; S.height := 0; S.shadow := 0; S.solid := True;
  S.lod := MakeRGB(120, 120, 120); S.mirror := 0; S.variants := 1;
  S.cmds := nil;
  begin
    for i := 0 to L.Count - 1 do
    begin
      t := SplitBy(L[i], ' ');
      if Length(t) = 0 then Continue;
      cmd := LowerCase(t[0]);
      if (cmd[1] = '#') or (cmd[1] = ';') then Continue;
      FillChar(c.v, SizeOf(c.v), 0);
      c.n := 0; c.img := ''; c.flower := False; c.rgb := MakeRGB(128, 128, 128);
      c.line := i;

      if cmd = 'width' then S.width := MaxD(1, N_(1))
      else if cmd = 'solid' then S.solid := N_(1) <> 0
      else if (cmd = 'lod') and (Length(t) > 1) then
      begin
        SetColor(t[1]);
        S.lod := c.rgb;
      end
      else if cmd = 'shadow' then S.shadow := MaxD(0, N_(1))
      else if (cmd = 'mirror') and (Length(t) > 1) then
      begin
        m := LowerCase(t[1]);
        if m = 'variant' then S.mirror := 1
        else if m = 'side' then S.mirror := 2
        else S.mirror := 0;
      end
      else if cmd = 'variants' then S.variants := Max(1, Round(N_(1)))
      else if ((cmd = 'rect') or (cmd = 'ellipse')) and (Length(t) >= 6) then
      begin
        if cmd = 'rect' then c.kind := scRect else c.kind := scEllipse;
        SetColor(t[1]);
        for j := 0 to 3 do c.v[j] := N_(2 + j);
        Push;
      end
      else if (cmd = 'poly') and (Length(t) >= 8) then
      begin
        c.kind := scPoly;
        SetColor(t[1]);
        n := Min(8, (Length(t) - 2) div 2);
        for j := 0 to n * 2 - 1 do c.v[j] := N_(2 + j);
        c.n := n;
        Push;
      end
      else if (cmd = 'image') and (Length(t) >= 6) then
      begin
        c.kind := scImage;
        c.img := t[1];
        for j := 0 to 3 do c.v[j] := N_(2 + j);
        Push;
      end
      else if (cmd = 'glow') and (Length(t) >= 5) then
      begin
        c.kind := scGlow;
        SetColor(t[1]);
        for j := 0 to 2 do c.v[j] := N_(2 + j);
        Push;
      end
      else if (cmd = 'rect') or (cmd = 'ellipse') or (cmd = 'poly') or (cmd = 'image') or (cmd = 'glow') then
        Warn('not enough numbers for "' + cmd + '"')
      else
        Warn('unknown command "' + t[0] + '"');
    end;
  end;

  // measure the height
  for i := 0 to High(S.cmds) do
    case S.cmds[i].kind of
      scRect, scImage: S.height := MaxD(S.height, MaxD(S.cmds[i].v[1], S.cmds[i].v[3]));
      scEllipse: S.height := MaxD(S.height, S.cmds[i].v[1] + S.cmds[i].v[3]);
      scPoly:
        for j := 0 to S.cmds[i].n - 1 do
          S.height := MaxD(S.height, S.cmds[i].v[j * 2 + 1]);
    end;
  Result := Length(S.cmds) > 0;
  if (not Result) and (warnings <> nil) then
    warnings.Add('nothing to draw yet - add rect, ellipse, poly or image lines');
end;

function LoadShapeFile(const path: string; out S: TShape): Boolean;
var
  L: TStringList;
begin
  Result := False;
  S.width := 1000; S.height := 0; S.shadow := 0; S.solid := True;
  S.lod := MakeRGB(120, 120, 120); S.mirror := 0; S.variants := 1;
  S.cmds := nil;
  if not FileExists(path) then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(path);
    except
      Exit;
    end;
    Result := LoadShapeLines(L, S, nil);
  finally
    L.Free;
  end;
end;

procedure LoadShapes;
var
  k: TSpriteKind;
begin
  for k := Low(TSpriteKind) to High(TSpriteKind) do
    if not LoadShapeFile(ShapePath(ShapeFile[k]), Shapes[k]) then
    begin
      SetLength(Shapes[k].cmds, 1);
      Shapes[k].cmds[0].kind := scRect;
      Shapes[k].cmds[0].flower := False;
      Shapes[k].cmds[0].rgb := MakeRGB(128, 128, 128);
      FillChar(Shapes[k].cmds[0].v, SizeOf(Shapes[k].cmds[0].v), 0);
      Shapes[k].cmds[0].v[0] := -250;
      Shapes[k].cmds[0].v[2] := 250;
      Shapes[k].cmds[0].v[3] := 800;
      Shapes[k].cmds[0].line := -1;
      Shapes[k].width := 500;
      Shapes[k].height := 800;
    end;
end;

function SpriteWidth(kind: TSpriteKind): Double;
begin
  Result := Shapes[kind].width;
end;

function IsSolid(kind: TSpriteKind): Boolean;
begin
  Result := Shapes[kind].solid;
end;

function GetTexture(const name: string): PSDL_Texture;
var
  i: Integer;
  surf: PSDL_Surface;
  tex: PSDL_Texture;
begin
  if TexNames = nil then TexNames := TStringList.Create;
  i := TexNames.IndexOf(name);
  if i >= 0 then Exit(TexList[i]);
  tex := nil;
  surf := SDL_LoadBMP(PChar(BitmapPath(name)));
  if surf <> nil then
  begin
    tex := SDL_CreateTextureFromSurface(Ren, surf);
    SDL_DestroySurface(surf);
  end;
  TexNames.Add(name);
  SetLength(TexList, TexNames.Count);
  TexList[High(TexList)] := tex;
  Result := tex;
end;

procedure FreeTextures;
var
  i: Integer;
begin
  for i := 0 to High(TexList) do
    if TexList[i] <> nil then SDL_DestroyTexture(TexList[i]);
  TexList := nil;
  if TexNames <> nil then TexNames.Clear;
end;

procedure ApplyLook;
var
  lk: TLook;
begin
  lk := CurLook;
  ColSkyTop := lk.skyTop;     ColSkyBottom := lk.skyBottom;
  ColFog := lk.fog;           ColMountain := lk.mountain;
  ColHills := lk.hills;
  ColGrassL := lk.grassL;     ColGrassD := lk.grassD;
  ColRoadL := lk.roadL;       ColRoadD := lk.roadD;
  FlowersOn := lk.flowers;
  if NightMode then
  begin
    NightMul := 1 - Night.darkness;
    ColSkyTop := Night.skyTop;
    ColSkyBottom := Night.skyBottom;
    ColFog := Night.fog;
    ColMountain := Shade(lk.mountain, NightMul * 0.6);
    ColHills := Shade(lk.hills, NightMul);
  end
  else
    NightMul := 1;
end;

procedure SetLook(season: Integer; night: Boolean);
begin
  SeasonIdx := EnsureRange(season, 0, 3);
  NightMode := night;
  RebuildNamedColors;
  ApplyLook;
  LoadShapes;
end;

procedure ReloadWorldGraphics;
begin
  ApplyLook;
  LoadModels;
  LoadShapes;
  FreeTextures;
end;

{ ------------------------------------------------------- track building }

function LastY: Double;
begin
  if Length(Segments) = 0 then Result := 0
  else Result := Segments[High(Segments)].p2.wy;
end;

function FindSegment(z: Double): Integer;
var
  n, cnt: Integer;
begin
  cnt := Length(Segments);
  if cnt = 0 then Exit(0);
  n := Floor(z / SegLen);
  Result := ((n mod cnt) + cnt) mod cnt;
end;

function RoadHeightAt(z: Double): Double;
var
  i: Integer;
begin
  if Length(Segments) = 0 then Exit(0);
  i := FindSegment(z);
  Result := Interp(Segments[i].p1.wy, Segments[i].p2.wy, PercentRemaining(z, SegLen));
end;

procedure AddSegment(ACurve, AY: Double);
var
  n: Integer;
  prevY: Double;
begin
  prevY := LastY;
  n := Length(Segments);
  SetLength(Segments, n + 1);
  Segments[n].index := n;
  Segments[n].p1.wx := 0; Segments[n].p1.wy := prevY; Segments[n].p1.wz := n * SegLen;
  Segments[n].p2.wx := 0; Segments[n].p2.wy := AY;    Segments[n].p2.wz := (n + 1) * SegLen;
  Segments[n].curve := ACurve;
  Segments[n].dark := ((n div RumbleLen) mod 2) = 1;
  Segments[n].special := 0;
  Segments[n].sprites := nil;
end;

procedure AddRoad(enter, hold, leave: Integer; ACurve, AY: Double);
var
  startY, endY: Double;
  n, total: Integer;
begin
  enter := EnsureRange(enter, 0, 5000);
  hold := EnsureRange(hold, 0, 5000);
  leave := EnsureRange(leave, 0, 5000);
  total := enter + hold + leave;
  if total = 0 then Exit;
  startY := LastY;
  endY := startY + AY * SegLen;
  for n := 0 to enter - 1 do
    AddSegment(EaseIn(0, ACurve, n / enter), EaseInOut(startY, endY, n / total));
  for n := 0 to hold - 1 do
    AddSegment(ACurve, EaseInOut(startY, endY, (enter + n) / total));
  for n := 0 to leave - 1 do
    AddSegment(EaseInOut(ACurve, 0, n / leave), EaseInOut(startY, endY, (enter + hold + n) / total));
end;

procedure AddSection(const s: TTrackSection);
var
  num: Integer;
begin
  num := Round(s.p[0]);
  case s.kind of
    tkStraight: AddRoad(num, num, num, 0, 0);
    tkCurve:    AddRoad(num, num, num, s.p[1], s.p[2]);
    tkHill:     AddRoad(num, num, num, 0, s.p[1]);
    tkRoad:     AddRoad(Round(s.p[0]), Round(s.p[1]), Round(s.p[2]), s.p[3], s.p[4]);
    tkRolling:
      begin
        AddRoad(num, num, num, 0, s.p[1] / 2);
        AddRoad(num, num, num, 0, -s.p[1]);
        AddRoad(num, num, num, CurveEasy, s.p[1]);
        AddRoad(num, num, num, 0, 0);
        AddRoad(num, num, num, -CurveEasy, s.p[1] / 2);
        AddRoad(num, num, num, 0, 0);
      end;
    tkSCurves:
      begin
        AddRoad(LenMedium, LenMedium, LenMedium, -CurveEasy, 0);
        AddRoad(LenMedium, LenMedium, LenMedium, CurveMedium, HillMedium);
        AddRoad(LenMedium, LenMedium, LenMedium, CurveEasy, -HillLow);
        AddRoad(LenMedium, LenMedium, LenMedium, -CurveEasy, HillMedium);
        AddRoad(LenMedium, LenMedium, LenMedium, -CurveMedium, -HillMedium);
      end;
    tkBumps:
      begin
        AddRoad(10, 10, 10, 0, 5);
        AddRoad(10, 10, 10, 0, -2);
        AddRoad(10, 10, 10, 0, -5);
        AddRoad(10, 10, 10, 0, 8);
        AddRoad(10, 10, 10, 0, 5);
        AddRoad(10, 10, 10, 0, -7);
        AddRoad(10, 10, 10, 0, 5);
        AddRoad(10, 10, 10, 0, -2);
      end;
    tkDownhill: AddRoad(num, num, num, -CurveEasy, -LastY / SegLen);
  end;
end;

procedure AddSprite(n: Integer; kind: TSpriteKind; offset: Double; variant: Integer);
var
  k: Integer;
begin
  if (n < 0) or (n >= Length(Segments)) then Exit;
  k := Length(Segments[n].sprites);
  SetLength(Segments[n].sprites, k + 1);
  Segments[n].sprites[k].kind := kind;
  Segments[n].sprites[k].offset := offset;
  Segments[n].sprites[k].variant := variant;
end;

procedure BuildSprites;
var
  n, cnt: Integer;
  c, prevC: Double;
begin
  cnt := Length(Segments);

  // billboards
  AddSprite(BillboardFirst, skBillboard, -BillboardOffset, 0);
  AddSprite(BillboardFirst + 25, skBillboard, BillboardOffset, 1);
  AddSprite(BillboardFirst + 50, skBillboard, -BillboardOffset, 2);
  n := BillboardFirst + 130;
  while n < cnt do
  begin
    AddSprite(n, skBillboard, BillboardOffset * RandomSign, Random(Shapes[skBillboard].variants));
    Inc(n, RandomRange2(BillboardSpacingMin, BillboardSpacingMax));
  end;

  // street lamps along the start straight
  n := 0;
  while n < LampUntil do
  begin
    AddSprite(n, skPole, -LampOffset, 0);
    AddSprite(n, skPole,  LampOffset, 0);
    Inc(n, LampSpacing);
  end;

  // a warning sign before each bend, chevrons on the outside of sharp bends
  for n := 30 to cnt - 1 do
  begin
    c := Segments[n].curve;
    prevC := Segments[n - 1].curve;
    if WarningEnabled and (Abs(c) >= 1) and (Abs(prevC) < 1) then
      AddSprite(n - WarningDistance, skWarning, WarningOffset, Round(SignD(c)));
    if ChevronEnabled and (Abs(c) >= ChevronMinCurve) and (n mod ChevronSpacing = 0) then
      AddSprite(n, skChevron, -SignD(c) * ChevronOffset, Round(SignD(c)));
  end;

  // bushes close to the road
  n := 6;
  while n < cnt do
  begin
    if Random < BushChance then
    begin
      if Random < FlowerRatio then
        AddSprite(n, skFlowerBush, RandomSign * (BushOffMin + Random * (BushOffMax - BushOffMin)),
                  Random(Max(1, Length(FlowerPalette))))
      else
        AddSprite(n, skBush, RandomSign * (BushOffMin + Random * (BushOffMax - BushOffMin)), 0);
    end;
    Inc(n, RandomRange2(BushSpacingMin, BushSpacingMax));
  end;

  // trees further out
  n := 10;
  while n < cnt do
  begin
    if Random < TreeChance then
    begin
      if Random < PineRatio then AddSprite(n, skPine, -(TreeOffMin + Random * (TreeOffMax - TreeOffMin)), 0)
      else AddSprite(n, skTree, -(TreeOffMin + Random * (TreeOffMax - TreeOffMin)), 0);
    end;
    if Random < TreeChance then
    begin
      if Random < PineRatio then AddSprite(n, skPine, TreeOffMin + Random * (TreeOffMax - TreeOffMin), 0)
      else AddSprite(n, skTree, TreeOffMin + Random * (TreeOffMax - TreeOffMin), 0);
    end;
    Inc(n, RandomRange2(TreeSpacingMin, TreeSpacingMax));
  end;
end;

function BuildTrack(const secs: TTrackSections; seed: LongInt): Boolean;
var
  i: Integer;
  def: TTrackSections;
begin
  Segments := nil;
  SetLength(SectionStarts, Length(secs));
  for i := 0 to High(secs) do
  begin
    SectionStarts[i] := Length(Segments);
    AddSection(secs[i]);
  end;
  Result := Length(Segments) >= 100;
  if not Result then   // empty or broken map: use the built-in one
  begin
    Segments := nil;
    def := DefaultTrackSections;
    for i := 0 to High(def) do AddSection(def[i]);
    for i := 0 to High(SectionStarts) do SectionStarts[i] := 0;
  end;

  StartIdx := (FindSegment(PlayerZ) + 2) mod Length(Segments);
  Segments[StartIdx].special := 1;
  Segments[(StartIdx + 1) mod Length(Segments)].special := 1;
  for i := 1 to RumbleLen do
    Segments[Length(Segments) - i].special := 2;
  TrackLength := Length(Segments) * SegLen;

  if seed <> 0 then RandSeed := seed;
  BuildSprites;
  BuildMinimap;
end;

procedure BuildTrackFromFile(seed: LongInt);
begin
  BuildTrack(LoadTrackSections(DataDir + 'track.txt'), seed);
end;

procedure ResetTraffic(maxSpeed: Double);
var
  i, j, ti, mi, cnt: Integer;
  total, r: Double;
begin
  SetLength(Cars, TrafficCount);
  cnt := Length(Segments);
  total := 0;
  for j := 0 to High(TrafficTypes) do total := total + TrafficTypes[j].weight;
  for i := 0 to High(Cars) do
  begin
    // vehicle type by weight
    ti := 0;
    if total > 0 then
    begin
      r := Random * total;
      for j := 0 to High(TrafficTypes) do
      begin
        r := r - TrafficTypes[j].weight;
        if r <= 0 then
        begin
          ti := j;
          Break;
        end;
      end;
    end;
    if ti < Length(TypeModel) then mi := TypeModel[ti] else mi := 0;
    if (mi < 0) or (mi >= Length(Models)) then mi := 0;
    Cars[i].m := mi;

    if Length(Models) > 0 then
    begin
      if Length(Models[mi].palette) > 0 then
        Cars[i].color := Models[mi].palette[Random(Length(Models[mi].palette))]
      else
        Cars[i].color := CarPalette[Random(Length(CarPalette))];
      Cars[i].w := Models[mi].width / RoadWidth;
      Cars[i].hit := Models[mi].hit;
      Cars[i].cruise := maxSpeed * (TrafficMinSpeed + Random * (TrafficMaxSpeed - TrafficMinSpeed)) *
                        Models[mi].speed;
    end
    else
    begin
      Cars[i].color := CarPalette[Random(Length(CarPalette))];
      Cars[i].w := 0.32;
      Cars[i].hit := 320;
      Cars[i].cruise := maxSpeed * 0.4;
    end;
    Cars[i].cruise := MinD(Cars[i].cruise, maxSpeed * 0.95);
    Cars[i].speed := Cars[i].cruise;
    Cars[i].offset := Random * 0.8 * RandomSign;
    if cnt > 40 then Cars[i].z := (30 + Floor(Random * (cnt - 30))) * SegLen
    else Cars[i].z := Random * cnt * SegLen;
    Cars[i].yaw := 0;
    if Random < TrafficDistracted then
    begin
      Cars[i].look := (2 + Random * 3) * SegLen;
      Cars[i].brake := maxSpeed * (0.08 + Random * 0.1);
    end
    else
    begin
      Cars[i].look := (10 + Random * 15) * SegLen;
      Cars[i].brake := maxSpeed * (0.35 + Random * 0.4);
    end;
  end;
end;

{ ------------------------------------------------------------ rendering }

procedure ApplyCameraView(const c: TCamera);
begin
  ViewDepth := 1 / Tan(c.fov / 2 * Pi / 180);
  ViewCX := ScreenW / 2 - Tan(c.yaw * Pi / 180) * ViewDepth * ScreenW / 2;
  ViewCY := ScreenH / 2 - Tan(c.pitch * Pi / 180) * ViewDepth * ScreenH / 2;
end;

procedure Project(var p: TProj; camX, camY, camZ: Double; back: Boolean = False);
begin
  p.cx := p.wx - camX;
  p.cy := p.wy - camY;
  if back then p.cz := camZ - p.wz else p.cz := p.wz - camZ;
  if Abs(p.cz) < 0.0001 then p.cz := 0.0001;
  p.scale := ViewDepth / p.cz;
  p.sx := ViewCX + p.scale * p.cx * ScreenW / 2;
  p.sy := ViewCY - p.scale * p.cy * ScreenH / 2;
  p.sw := p.scale * RoadWidth * ScreenW / 2;
end;

procedure DrawBackground(playerY: Double);
var
  x, y, yEnd: Integer;
  u, h, baseY, sunX, sunY, sunR, dy, shift, top: Double;
begin
  yEnd := Round(ClampD(ViewCY + 40, 0, ScreenH));
  y := 0;
  while y < yEnd do
  begin
    SetCol(Mix(ColSkyTop, ColSkyBottom, ClampD(y / MaxD(ViewCY, 1), 0, 1)));
    FillR(0, y, ScreenW, 4);
    Inc(y, 4);
  end;

  shift := ViewCX - ScreenW / 2;
  sunX := ScreenW * (WrapUnit(0.7 - SkyOffset) * 1.6 - 0.3) + shift;
  sunY := ViewCY - ScreenH * 0.3;
  sunR := 40;
  if NightMode then
  begin
    // stars, then a moon instead of the sun
    for x := 0 to Min(Night.stars, 1000) - 1 do
    begin
      u := WrapUnit(RndA[x] - SkyOffset * 0.5) * ScreenW + shift;
      h := RndB[x] * (ViewCY - 30);
      SetCol(Shade(MakeRGB(255, 255, 240), 0.45 + 0.55 * RndC[x]));
      if RndC[x] > 0.85 then FillR(u, h, 2, 2) else FillR(u, h, 1, 1);
    end;
    SetCol(ColMoon, 40);
    FillEllipse(sunX, sunY, 46, 46);
    SetCol(ColMoon);
    sunR := 28;
  end
  else
    SetCol(ColSun);
  y := -Round(sunR);
  while y <= Round(sunR) do
  begin
    dy := Sqrt(sunR * sunR - y * y);
    FillR(sunX - dy, sunY + y, dy * 2, 1);
    Inc(y);
  end;
  if NightMode then
  begin
    SetCol(Shade(ColMoon, 0.82));
    FillEllipse(sunX - 9, sunY - 6, 7, 6);
    FillEllipse(sunX + 8, sunY + 9, 5, 4);
  end;

  baseY := ViewCY + playerY * 0.0025;

  SetCol(ColMountain);
  x := 0;
  while x < ScreenW do
  begin
    u := (x - shift) / ScreenW + SkyOffset;
    h := 70 + 40 * Sin(u * 2 * Pi) + 25 * Sin(u * 2 * Pi * 3 + 1.3) + 12 * Sin(u * 2 * Pi * 7 + 0.4);
    FillR(x, baseY - h, 3, h + 4);
    Inc(x, 3);
  end;

  SetCol(ColHills);
  x := 0;
  while x < ScreenW do
  begin
    u := (x - shift) / ScreenW + HillOffset;
    h := 28 + 16 * Sin(u * 2 * Pi * 2 + 2) + 8 * Sin(u * 2 * Pi * 5);
    top := baseY - h;
    if top < ScreenH then FillR(x, top, 3, ScreenH - top);
    Inc(x, 3);
  end;
end;

procedure DrawRoadQuad(const nearP, farP: TProj; dark: Boolean; special: Integer; fog, clip: Double);
var
  x1, y1, w1, x2, y2, w2, r1, r2, l1, l2, lx1, lx2: Double;
  grass, road, rumble: TRGB;
  lane: Integer;
begin
  x1 := nearP.sx; y1 := nearP.sy; w1 := nearP.sw;
  x2 := farP.sx;  y2 := farP.sy;  w2 := farP.sw;

  if dark then
  begin
    grass := ColGrassD; road := ColRoadD; rumble := ColRumbleD;
  end
  else
  begin
    grass := ColGrassL; road := ColRoadL; rumble := ColRumbleL;
  end;
  if special = 1 then begin road := ColStart; rumble := ColStart; end;
  if special = 2 then begin road := ColFinish; rumble := ColFinish; end;

  SetCol(Fogged(grass, fog));
  FillPoly(0, ScreenW, y1, 0, ScreenW, y2, clip);

  r1 := w1 / 6; r2 := w2 / 6;
  SetCol(Fogged(rumble, fog));
  FillPoly(x1 - w1 - r1, x1 - w1, y1, x2 - w2 - r2, x2 - w2, y2, clip);
  FillPoly(x1 + w1, x1 + w1 + r1, y1, x2 + w2, x2 + w2 + r2, y2, clip);

  SetCol(Fogged(road, fog));
  FillPoly(x1 - w1, x1 + w1, y1, x2 - w2, x2 + w2, y2, clip);

  if (special = 0) and not dark then
  begin
    SetCol(Fogged(ColLane, fog));
    l1 := w1 / 32; l2 := w2 / 32;
    lx1 := x1 - w1 + 2 * w1 / Lanes;
    lx2 := x2 - w2 + 2 * w2 / Lanes;
    for lane := 1 to Lanes - 1 do
    begin
      FillPoly(lx1 - l1 / 2, lx1 + l1 / 2, y1, lx2 - l2 / 2, lx2 + l2 / 2, y2, clip);
      lx1 := lx1 + 2 * w1 / Lanes;
      lx2 := lx2 + 2 * w2 / Lanes;
    end;
  end;
end;

{ Vehicle drawn from its 3D model: rotated by the yaw, projected with the
  same perspective as the road, back faces dropped, painted far to near.
  (cx, by) = bottom centre of the rear on screen, u = pixels per unit. }
procedure DrawCarAngle(const M: TModel; cx, by, u: Double; const paint: TRGB; fog, angle, clip: Double);
type
  TTmpFace = record
    p: TQuad;
    k, depth: Double;
    fi: Integer;
  end;
var
  tmp: array[0..MaxDrawFaces - 1] of TTmpFace;
  order: array[0..MaxDrawFaces - 1] of Integer;
  px, py: array[0..3] of Double;
  nf, i, j, t, di: Integer;
  cz, ang, ca, sa, baseX, baseY, hw, L, rnx, rny, rnz, lam, s, gz: Double;
  mc: TV3;
  col: TRGB;
  dc: ^TModelDecal;

  function ToCam(const v: TV3): TV3;
  var
    zc: Double;
  begin
    zc := v.z - L / 2;
    Result.x := baseX + v.x * ca + zc * sa;
    Result.y := baseY - v.y;
    Result.z := cz + L / 2 - v.x * sa + zc * ca;
  end;

  procedure ProjXY(const p: TV3; out sx, sy: Double);
  var
    f: Double;
  begin
    f := u * cz / MaxD(p.z, 1);
    sx := ViewCX + p.x * f;
    sy := ViewCY + p.y * f;
  end;

  function Resolve(const cs: TColSpec): TRGB;
  begin
    if cs.body then Result := Shade(paint, cs.k) else Result := cs.rgb;
  end;

begin
  if not BeginClip(clip) then Exit;
  hw := M.width / 2 * u;
  L := M.length;

  if (hw < 3) or (Length(M.faces) = 0) then   // far away: a coloured block
  begin
    SetCol(Fogged(paint, fog));
    FillR(cx - hw, by - M.height * u, hw * 2, M.height * u);
    EndClip;
    Exit;
  end;

  ang := angle;
  ca := Cos(ang);
  sa := Sin(ang);
  cz := ViewDepth * (ScreenW / 2) / u;
  baseX := (cx - ViewCX) / u;
  baseY := (by - ViewCY) / u;

  // too close to the camera to draw sensibly
  if (ToCam(V3(-M.width / 2, 0, 0)).z < 60) or (ToCam(V3(M.width / 2, 0, 0)).z < 60) or
     (ToCam(V3(-M.width / 2, 0, L)).z < 60) or (ToCam(V3(M.width / 2, 0, L)).z < 60) then
  begin
    EndClip;
    Exit;
  end;

  // shadow: the footprint on the road
  for i := 0 to 3 do
  begin
    if (i = 0) or (i = 3) then s := -M.width / 2 * 1.08 else s := M.width / 2 * 1.08;
    if i < 2 then gz := -25 else gz := L + 25;
    ProjXY(ToCam(V3(s, 0, gz)), px[i], py[i]);
  end;
  SetCol(MakeRGB(0, 0, 0), 80);
  FillConvex(px, py, 4);

  // visible faces
  nf := 0;
  for i := 0 to High(M.faces) do
  begin
    if nf >= MaxDrawFaces then Break;
    for j := 0 to 3 do tmp[nf].p[j] := ToCam(M.faces[i].p[j]);
    mc := QuadCenter(tmp[nf].p);
    rnx := M.faces[i].n.x * ca + M.faces[i].n.z * sa;
    rny := -M.faces[i].n.y;
    rnz := -M.faces[i].n.x * sa + M.faces[i].n.z * ca;
    if rnx * mc.x + rny * mc.y + rnz * mc.z >= 0 then Continue;   // facing away
    lam := -(rnx * 0.35 + rny * 0.8 + rnz * 0.48);
    tmp[nf].k := 0.62 + 0.5 * MaxD(0, lam);
    tmp[nf].depth := mc.x * mc.x + mc.y * mc.y + mc.z * mc.z;
    tmp[nf].fi := i;
    Inc(nf);
  end;

  // far faces first
  for i := 0 to nf - 1 do order[i] := i;
  for i := 1 to nf - 1 do
  begin
    t := order[i];
    j := i - 1;
    while (j >= 0) and (tmp[order[j]].depth < tmp[t].depth) do
    begin
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := t;
  end;

  for i := 0 to nf - 1 do
  begin
    t := order[i];
    for j := 0 to 3 do ProjXY(tmp[t].p[j], px[j], py[j]);
    col := Shade(Resolve(M.faces[tmp[t].fi].col), tmp[t].k);
    if (HighlightLine >= 0) and (M.faces[tmp[t].fi].line = HighlightLine) then
      col := Mix(col, MakeRGB(255, 230, 0), 0.6);
    SetCol(Fogged(col, fog));
    FillConvex(px, py, 4);
    for di := 0 to High(M.faces[tmp[t].fi].decals) do
    begin
      dc := @M.decals[M.faces[tmp[t].fi].decals[di]];
      for j := 0 to 3 do ProjXY(ToCam(dc^.p[j]), px[j], py[j]);
      if dc^.glow then col := Resolve(dc^.col)
      else col := Shade(Resolve(dc^.col), tmp[t].k);
      if (HighlightLine >= 0) and (dc^.line = HighlightLine) then
        col := Mix(col, MakeRGB(255, 230, 0), 0.6);
      if dc^.glow then SetCol(FoggedLit(col, fog)) else SetCol(Fogged(col, fog));
      FillConvex(px, py, 4);
      if dc^.glow and NightMode then
        AddGlow((px[0] + px[1] + px[2] + px[3]) / 4, (py[0] + py[1] + py[2] + py[3]) / 4,
                MaxD(MaxD(px[0], MaxD(px[1], MaxD(px[2], px[3]))) - MinD(px[0], MinD(px[1], MinD(px[2], px[3]))),
                     MaxD(py[0], MaxD(py[1], MaxD(py[2], py[3]))) - MinD(py[0], MinD(py[1], MinD(py[2], py[3])))) * 1.6 + 3,
                FoggedLit(col, fog), clip);
    end;
  end;
  EndClip;
end;

procedure DrawCar(const M: TModel; cx, by, u: Double; const paint: TRGB; fog, yaw, clip: Double;
                  front: Boolean = False);
begin
  if front then DrawCarAngle(M, cx, by, u, paint, fog, yaw * 0.4 + Pi, clip)
  else DrawCarAngle(M, cx, by, u, paint, fog, yaw * 0.4, clip);
end;

procedure DrawShapeAt(const S: TShape; const sp: TSprite; sx, sy, u, clip, fog: Double);
var
  i, j, vi: Integer;
  w, h, m, x0, x1, y0, y1: Double;
  px, py: array[0..7] of Double;
  col: TRGB;
  tex: PSDL_Texture;
  dst: TSDL_FRect;
begin
  w := S.width * u;
  if (u <= 0) or (w > ScreenW * 3) then Exit;
  if not BeginClip(clip) then Exit;

  if w < 5 then   // far away: a tiny block
  begin
    h := MinD(S.height * u, w * 2.5);
    SetCol(Fogged(S.lod, fog));
    FillR(sx - w / 2, sy - h, w, h);
    EndClip;
    Exit;
  end;

  case S.mirror of
    1: if sp.variant < 0 then m := -1 else m := 1;
    2: m := -SignD(sp.offset);
  else
    m := 1;
  end;

  if S.shadow > 0 then
  begin
    SetCol(MakeRGB(0, 0, 0), 45);
    FillEllipse(sx, sy, S.shadow * u, 60 * u);
  end;

  for i := 0 to High(S.cmds) do
    with S.cmds[i] do
    begin
      if flower and not FlowersOn then Continue;    // no flowers this season
      if kind <> scImage then
      begin
        if flower and (Length(FlowerPalette) > 0) then
          col := FlowerPalette[Abs(sp.variant) mod Length(FlowerPalette)]
        else
          col := rgb;
        if (ShapeHighlightLine >= 0) and (line = ShapeHighlightLine) then
          col := Mix(col, MakeRGB(255, 230, 0), 0.6);
        SetCol(Fogged(col, fog));
      end;
      case kind of
        scGlow:
          if NightMode then
            AddGlow(sx + m * v[0] * u, sy - v[1] * u, v[2] * u, FoggedLit(col, fog), clip);
        scRect:
          begin
            x0 := sx + m * v[0] * u; x1 := sx + m * v[2] * u;
            y0 := sy - v[1] * u;     y1 := sy - v[3] * u;
            FillR(MinD(x0, x1), MinD(y0, y1), Abs(x1 - x0), Abs(y1 - y0));
          end;
        scEllipse:
          FillEllipse(sx + m * v[0] * u, sy - v[1] * u, v[2] * u, v[3] * u);
        scPoly:
          begin
            for j := 0 to n - 1 do
            begin
              px[j] := sx + m * v[j * 2] * u;
              py[j] := sy - v[j * 2 + 1] * u;
            end;
            FillConvex(px, py, n);
          end;
        scImage:
          begin
            x0 := sx + m * v[0] * u; x1 := sx + m * v[2] * u;
            y0 := sy - v[1] * u;     y1 := sy - v[3] * u;
            dst.x := MinD(x0, x1); dst.y := MinD(y0, y1);
            dst.w := Abs(x1 - x0); dst.h := Abs(y1 - y0);
            vi := Abs(sp.variant) mod Max(1, S.variants);
            tex := GetTexture(StringReplace(img, '{v}', IntToStr(vi), [rfReplaceAll]));
            if tex <> nil then
              SDL_RenderTexture(Ren, tex, nil, @dst)
            else
            begin
              SetCol(Fogged(MakeRGB(200, 200, 200), fog));
              SDL_RenderFillRect(Ren, @dst);
            end;
            if NightMul < 0.999 then
            begin
              SetCol(MakeRGB(0, 0, 0), Round(255 * (1 - NightMul)));
              SDL_RenderFillRect(Ren, @dst);
            end;
            if fog < 0.999 then
            begin
              SetCol(ColFog, Round(255 * (1 - fog)));
              SDL_RenderFillRect(Ren, @dst);
            end;
            if (ShapeHighlightLine >= 0) and (line = ShapeHighlightLine) then
            begin
              SetCol(MakeRGB(255, 230, 0));
              SDL_RenderRect(Ren, @dst);
            end;
          end;
      end;
    end;
  EndClip;
end;

procedure DrawSprite(const sp: TSprite; sx, sy, u, clip, fog: Double);
begin
  DrawShapeAt(Shapes[sp.kind], sp, sx, sy, u, clip, fog);
end;

{ main view: background, road, scenery, traffic and (optionally) our car }
procedure RenderWorld(const c: TCamera; carZ, playerX: Double; showPlayer: Boolean;
                      const playerPaint: TRGB; steer, bounce: Double);
var
  cnt, baseIdx, playerIdx, n, idx, i, k, dist: Integer;
  basePct, playerPct, playerY, maxy, x, dx, loopZ, camPos, camX, camY: Double;
  pct, sc, sx, sy, u: Double;
  S: PSegment;
  carSeg: TIntArray;
  playerDrawn: Boolean;

  { two beams of light on the road ahead of our car }
  procedure DrawBeams;
  var
    kk, ii: Integer;
    B: PSegment;
    x1, x2, w1, w2, a: Double;
  begin
    SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_ADD);
    for kk := 1 to 16 do
    begin
      ii := (playerIdx + kk) mod cnt;
      B := @Segments[ii];
      if (B^.p1.cz <= ViewDepth) or (B^.p2.sy >= B^.p1.sy) then Continue;
      x1 := B^.p1.sx + B^.p1.scale * playerX * RoadWidth * ScreenW / 2;
      x2 := B^.p2.sx + B^.p2.scale * playerX * RoadWidth * ScreenW / 2;
      w1 := B^.p1.sw * (0.22 + kk * 0.012);
      w2 := B^.p2.sw * (0.22 + (kk + 1) * 0.012);
      a := 60 * (1 - kk / 17);
      SDL_SetRenderDrawColor(Ren, 255, 235, 170, Round(a));
      FillPoly(x1 - w1, x1 + w1, B^.p1.sy, x2 - w2, x2 + w2, B^.p2.sy, B^.clip);
    end;
    SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  end;

  procedure DrawPlayerNow;
  begin
    if playerDrawn then Exit;
    playerDrawn := True;
    if not showPlayer then Exit;
    if NightMode and Night.headlights then DrawBeams;
    if Assigned(BeforePlayerHook) then BeforePlayerHook();
    if (PlayerModel >= 0) and (PlayerModel < Length(Models)) then
      DrawCar(Models[PlayerModel], PlayerSX, PlayerBY + bounce, PlayerU, playerPaint, 1, steer, ScreenH);
    if Assigned(AfterPlayerHook) then AfterPlayerHook();
  end;

begin
  cnt := Length(Segments);
  if cnt = 0 then Exit;
  ApplyCameraView(c);
  dist := Min(DrawDistance, cnt);

  carZ := Increase(carZ, 0, TrackLength);
  camPos := Increase(carZ, -c.distance, TrackLength);
  baseIdx := FindSegment(camPos);
  basePct := PercentRemaining(camPos, SegLen);
  playerIdx := FindSegment(carZ);
  playerPct := PercentRemaining(carZ, SegLen);
  playerY := Interp(Segments[playerIdx].p1.wy, Segments[playerIdx].p2.wy, playerPct);
  camX := playerX * RoadWidth + c.side;
  camY := playerY + c.height;

  SetLength(carSeg, Length(Cars));
  for i := 0 to High(Cars) do carSeg[i] := FindSegment(Cars[i].z);

  BeginGlows;
  DrawBackground(playerY);

  maxy := ScreenH;
  x := 0;
  dx := -(Segments[baseIdx].curve * basePct);
  for n := 0 to dist - 1 do
  begin
    idx := (baseIdx + n) mod cnt;
    S := @Segments[idx];
    if idx < baseIdx then loopZ := TrackLength else loopZ := 0;
    S^.fog := 1 / Exp(Sqr(n / DrawDistance) * FogDensity);
    S^.clip := maxy;
    Project(S^.p1, camX - x,      camY, camPos - loopZ);
    Project(S^.p2, camX - x - dx, camY, camPos - loopZ);
    x := x + dx;
    dx := dx + S^.curve;
    if (S^.p1.cz <= ViewDepth) or (S^.p2.sy >= S^.p1.sy) or (S^.p2.sy >= maxy) then
      Continue;
    DrawRoadQuad(S^.p1, S^.p2, S^.dark, S^.special, S^.fog, maxy);
    maxy := S^.p2.sy;
  end;

  // where our car is on screen (placed like the traffic)
  S := @Segments[playerIdx];
  sc := Interp(S^.p1.scale, S^.p2.scale, playerPct);
  PlayerU := sc * ScreenW / 2;
  PlayerSX := Interp(S^.p1.sx, S^.p2.sx, playerPct) + sc * playerX * RoadWidth * ScreenW / 2;
  PlayerBY := Interp(S^.p1.sy, S^.p2.sy, playerPct);

  playerDrawn := False;
  for n := dist - 1 downto 1 do
  begin
    idx := (baseIdx + n) mod cnt;
    S := @Segments[idx];
    if S^.p1.cz <= ViewDepth then
    begin
      if idx = playerIdx then DrawPlayerNow;
      Continue;
    end;

    for i := 0 to High(Cars) do
      if carSeg[i] = idx then
      begin
        pct := PercentRemaining(Cars[i].z, SegLen);
        sc := Interp(S^.p1.scale, S^.p2.scale, pct);
        u := sc * ScreenW / 2;
        sx := Interp(S^.p1.sx, S^.p2.sx, pct) + sc * Cars[i].offset * RoadWidth * ScreenW / 2;
        sy := Interp(S^.p1.sy, S^.p2.sy, pct);
        if (Cars[i].m < Length(Models)) and (Models[Cars[i].m].width * u < ScreenW * 0.9) then
          DrawCar(Models[Cars[i].m], sx, sy, u, Cars[i].color, S^.fog, Cars[i].yaw, S^.clip);
      end;

    for k := 0 to High(S^.sprites) do
      DrawSprite(S^.sprites[k],
                 S^.p1.sx + S^.p1.scale * S^.sprites[k].offset * RoadWidth * ScreenW / 2,
                 S^.p1.sy, S^.p1.scale * ScreenW / 2, S^.clip, S^.fog);

    if idx = playerIdx then DrawPlayerNow;
  end;
  DrawPlayerNow;
  FlushGlows;
  DrawWeather;
end;

{ view behind the car into a texture; the mirror keeps its own camera }
procedure RenderMirror(tex: PSDL_Texture; carZ, playerX: Double);
var
  cnt, playerIdx, n, idx, i, k, dist: Integer;
  camZ, camY, playerPct, x, dx, maxy, loopZ, pct, sc, u, sx, sy: Double;
  savedSky, savedHill: Double;
  S: PSegment;
  carSeg: TIntArray;
begin
  cnt := Length(Segments);
  if (tex = nil) or (cnt = 0) then Exit;
  ViewDepth := CameraDepth;
  ViewCX := ScreenW / 2;
  ViewCY := ScreenH / 2;
  dist := Min(MirrorDistance, cnt);

  SDL_SetRenderTarget(Ren, tex);
  SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
  SDL_RenderClear(Ren);

  camZ := Increase(carZ, 0, TrackLength);
  playerIdx := FindSegment(camZ);
  playerPct := PercentRemaining(camZ, SegLen);
  camY := Interp(Segments[playerIdx].p1.wy, Segments[playerIdx].p2.wy, playerPct) + MirrorCamHeight;

  SetLength(carSeg, Length(Cars));
  for i := 0 to High(Cars) do carSeg[i] := FindSegment(Cars[i].z);

  BeginGlows;
  savedSky := SkyOffset; savedHill := HillOffset;
  SkyOffset := WrapUnit(SkyOffset + 0.5);
  HillOffset := WrapUnit(HillOffset + 0.5);
  DrawBackground(camY - MirrorCamHeight);
  SkyOffset := savedSky; HillOffset := savedHill;

  maxy := ScreenH;
  x := 0;
  dx := 0;
  for n := 0 to dist - 1 do
  begin
    idx := (playerIdx - n + cnt) mod cnt;
    S := @Segments[idx];
    if idx > playerIdx then loopZ := TrackLength else loopZ := 0;
    S^.fog := 1 / Exp(Sqr(n / MirrorDistance) * FogDensity);
    S^.clip := maxy;
    Project(S^.p2, playerX * RoadWidth - x,      camY, camZ + loopZ, True);
    Project(S^.p1, playerX * RoadWidth - x - dx, camY, camZ + loopZ, True);
    x := x + dx;
    dx := dx + S^.curve;
    if (S^.p2.cz <= ViewDepth) or (S^.p1.sy >= S^.p2.sy) or (S^.p1.sy >= maxy) then
      Continue;
    DrawRoadQuad(S^.p2, S^.p1, S^.dark, S^.special, S^.fog, maxy);
    maxy := S^.p1.sy;
  end;

  for n := dist - 1 downto 1 do
  begin
    idx := (playerIdx - n + cnt) mod cnt;
    S := @Segments[idx];
    if S^.p2.cz <= ViewDepth then Continue;

    for k := 0 to High(S^.sprites) do
      DrawSprite(S^.sprites[k],
                 S^.p1.sx + S^.p1.scale * S^.sprites[k].offset * RoadWidth * ScreenW / 2,
                 S^.p1.sy, S^.p1.scale * ScreenW / 2, S^.clip, S^.fog);

    for i := 0 to High(Cars) do
      if carSeg[i] = idx then
      begin
        pct := PercentRemaining(Cars[i].z, SegLen);
        sc := Interp(S^.p1.scale, S^.p2.scale, pct);
        if sc <= 0 then Continue;
        u := sc * ScreenW / 2;
        sx := Interp(S^.p1.sx, S^.p2.sx, pct) + sc * Cars[i].offset * RoadWidth * ScreenW / 2;
        sy := Interp(S^.p1.sy, S^.p2.sy, pct);
        if (Cars[i].m < Length(Models)) and (Models[Cars[i].m].width * u < ScreenW * 0.9) then
          DrawCar(Models[Cars[i].m], sx, sy, u, Cars[i].color, S^.fog, 0, S^.clip, True);
      end;
  end;

  FlushGlows;
  SDL_SetRenderTarget(Ren, nil);
end;

{ ------------------------------------------------------------- minimap }

procedure BuildMinimap;
var
  i, cnt: Integer;
  rx, rz: TNumArray;
  heading, k, totalCurve, x, z, ex, ez, t: Double;
  minX, maxX, minZ, maxZ, sc, midX, midZ: Double;
begin
  cnt := Length(Segments);
  SetLength(MapNX, cnt);
  SetLength(MapNY, cnt);
  if cnt = 0 then Exit;
  totalCurve := 0;
  for i := 0 to cnt - 1 do totalCurve := totalCurve + Segments[i].curve;
  if Abs(totalCurve) > 1 then k := 2 * Pi / totalCurve else k := 0.005;

  SetLength(rx, cnt + 1);
  SetLength(rz, cnt + 1);
  heading := 0; x := 0; z := 0;
  for i := 0 to cnt - 1 do
  begin
    rx[i] := x; rz[i] := z;
    heading := heading + Segments[i].curve * k;
    x := x + Sin(heading);
    z := z + Cos(heading);
  end;
  rx[cnt] := x; rz[cnt] := z;

  ex := rx[cnt] - rx[0];
  ez := rz[cnt] - rz[0];
  minX := 1e30; maxX := -1e30; minZ := 1e30; maxZ := -1e30;
  for i := 0 to cnt do
  begin
    t := i / cnt;
    rx[i] := rx[i] - ex * t;
    rz[i] := rz[i] - ez * t;
    minX := MinD(minX, rx[i]); maxX := MaxD(maxX, rx[i]);
    minZ := MinD(minZ, rz[i]); maxZ := MaxD(maxZ, rz[i]);
  end;

  sc := 0.88 / MaxD(MaxD(maxX - minX, maxZ - minZ), 1e-6);
  midX := (minX + maxX) / 2;
  midZ := (minZ + maxZ) / 2;
  for i := 0 to cnt - 1 do
  begin
    MapNX[i] := 0.5 + (rx[i] - midX) * sc;
    MapNY[i] := 0.5 - (rz[i] - midZ) * sc;
  end;
end;

procedure DrawMinimap(x, y, size: Single; carZ: Double; showCars: Boolean;
                      hiFrom, hiTo: Integer; bgAlpha: Byte = 130);
var
  i, n, cnt: Integer;
  rects: array of TSDL_FRect;
  px, py: Double;
begin
  cnt := Length(MapNX);
  if cnt = 0 then Exit;
  SetCol(MakeRGB(0, 0, 0), bgAlpha);
  FillR(x, y, size, size);

  SetLength(rects, (cnt + 1) div 2);
  n := 0;
  i := 0;
  while i < cnt do
  begin
    rects[n].x := x + MapNX[i] * size - 1.5;
    rects[n].y := y + MapNY[i] * size - 1.5;
    rects[n].w := 3;
    rects[n].h := 3;
    Inc(n);
    Inc(i, 2);
  end;
  SetCol(MakeRGB(185, 185, 185));
  if n > 0 then SDL_RenderFillRects(Ren, @rects[0], n);

  if (hiFrom >= 0) and (hiTo >= hiFrom) then
  begin
    SetCol(MakeRGB(255, 200, 40));
    for i := Max(0, hiFrom) to Min(cnt - 1, hiTo) do
      FillR(x + MapNX[i] * size - 2.5, y + MapNY[i] * size - 2.5, 5, 5);
  end;

  if StartIdx < cnt then
  begin
    SetCol(MakeRGB(255, 255, 255));
    FillR(x + MapNX[StartIdx] * size - 4, y + MapNY[StartIdx] * size - 1, 8, 2);
  end;

  if showCars then
    for i := 0 to High(Cars) do
    begin
      n := FindSegment(Cars[i].z);
      SetCol(Cars[i].color);
      FillR(x + MapNX[n] * size - 2, y + MapNY[n] * size - 2, 4, 4);
    end;

  if carZ >= 0 then
  begin
    n := FindSegment(carZ);
    px := x + MapNX[n] * size;
    py := y + MapNY[n] * size;
    SetCol(MakeRGB(255, 255, 255));
    FillR(px - 5, py - 5, 10, 10);
    SetCol(PlayerColor);
    FillR(px - 3, py - 3, 6, 6);
  end;
end;

end.
