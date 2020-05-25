import geom as area
import math
import re
import copy
from coords import Coords
import sim

class Point:
    def __init__(self, x, y, z):
        self.x = x
        self.y = y
        self.z = z
        
    def dist(self, p):
        dx = math.fabs(p.x - self.x)
        dy = math.fabs(p.y - self.y)
        dz = math.fabs(p.z - self.z)
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    
    def __mul__(self, value):
        return Point(self.x * value, self.y * value, self.z * value)
    
    def __add__(self, p):
        return Point(self.x + p.x, self.y + p.y, self.z + p.z)
    
    def __sub__(self, p):
        return Point(self.x - p.x, self.y - p.y, self.z - p.z)

class Line:
    def __init__(self, p0, p1, rapid, tool_number):
        self.p0 = p0
        self.p1 = p1
        self.rapid = rapid
        self.tool_number = tool_number
        
    def Length(self):
        return self.p0.dist(self.p1)
        
x_for_cut = 0
y_for_cut = 0
z_for_cut = 0
        
class VoxelCyl:
    def __init__(self, radius, z, color):
        self.radius = int(radius)
        self.z_bottom = int(z)
        self.z_top = int(z) + 1
        self.color = color

    def cut(self):
        sim.set_current_color(self.color)
        sim.remove_cylinder(int(x_for_cut), int(y_for_cut), z_for_cut + int(self.z_bottom), int(x_for_cut), int(y_for_cut), z_for_cut + int(self.z_top), int(self.radius))
        
    def draw(self):

        for i in range(0, 21):
            a = 0.31415926 * i
            x = float(x_for_cut) + self.radius * math.cos(a)
            y = float(y_for_cut) + self.radius * math.sin(a)
            z_bottom = float(z_for_cut) + self.z_bottom
            z_top = float(z_for_cut) + self.z_top

            sim.drawline3d(x, y, z_bottom, x, y, z_top, self.color)
            
            if i > 0:
                sim.drawline3d(prevx, prevy, prevz_bottom, x, y, z_bottom, self.color)
                sim.drawline3d(prevx, prevy, prevz_top, x, y, z_top, self.color)
            prevx = x
            prevy = y
            prevz_bottom = z_bottom
            prevz_top = z_top
        
class Tool:
    def __init__(self, span_list):
        # this is made from a list of (area.Span, colour_ref)
        # the spans should be defined with the y-axis representing the centre of the tool, with the tip of the tool being defined at y = 0
        self.span_list = span_list
        self.cylinders = []
        self.cylinders_calculated = False
        self.calculate_cylinders()
        
    def calculate_span_cylinders(self, span, color):
        sz = span.p.y * toolpath.coords.voxels_per_mm
        ez = span.v.p.y * toolpath.coords.voxels_per_mm
        
        z = sz
        while z < ez:
            # make a line at this z
            intersection_line = area.Span(area.Point(0, z), area.Vertex(0, area.Point(300, z), area.Point(0, 0)), False)
            intersections = span.Intersect(intersection_line)
            if len(intersections):
                radius = intersections[0].x * toolpath.coords.voxels_per_mm
                self.cylinders.append(VoxelCyl(radius, z * toolpath.coords.voxels_per_mm, color))
            z += 1/toolpath.coords.voxels_per_mm
            
    def refine_cylinders(self):
        cur_cylinder = None
        old_cylinders = self.cylinders
        self.cylinders = []
        for cylinder in old_cylinders:
            if cur_cylinder == None:
                cur_cylinder = cylinder
            else:
                if cur_cylinder.radius == cylinder.radius:
                    cur_cylinder.z_top = cylinder.z_top
                else:
                    self.cylinders.append(cur_cylinder)
                    cur_cylinder = cylinder
        if cur_cylinder != None:
            self.cylinders.append(cur_cylinder)                    
        
    def calculate_cylinders(self):
        self.cylinders = []
        for span_and_color in self.span_list:
            self.calculate_span_cylinders(span_and_color[0], span_and_color[1])
            
        self.refine_cylinders()
                                  
        self.cylinders_calculated = True
            
    def cut(self, x, y, z):
        global x_for_cut
        global y_for_cut
        global z_for_cut
        x_for_cut = x
        y_for_cut = y
        z_for_cut = z
        for cylinder in self.cylinders:
            cylinder.cut()
            
    def draw(self, x, y, z):
        global x_for_cut
        global y_for_cut
        global z_for_cut
        x_for_cut = x
        y_for_cut = y
        z_for_cut = z
        for cylinder in self.cylinders:
            cylinder.draw()

def GetSimToolDefinition(tool):
    GRAY = (0.5, 0.5, 0.5)
    RED = (0.7, 0.0, 0.0)
    BLUE = (0.0, 0.0, 0.3)
        
    span_list = []
    height_above_cutting_edge = 30.0
    r = tool.diameter/2.0
    h = tool.cutting_edge_height
    cr = tool.corner_radius
    
    if tool.type == TOOL_TYPE_DRILL or tool.type == TOOL_TYPE_CENTREDRILL:
        max_cutting_height = 0.0
        radius_at_cutting_height = r
        edge_angle = tool.cutting_edge_angle
        flat_radius = tool.flat_radius
        if (edge_angle < 0.01) or (r < flat_radius):
            span_list.append([geom.Span(geom.Point(flat_radius, 0), geom.Vertex(geom.Point(flat_radius, h)), False), GRAY])
            span_list.append([geom.Span(geom.Point(flat_radius, h), geom.Vertex(geom.Point(flat_radius, h + height_above_cutting_edge)), False), RED])
        else:
            rad_diff = r - flat_radius
            max_cutting_height = rad_diff / math.tan(edge_angle * 0.0174532925199432)
            radius_at_cutting_height = (h/max_cutting_height) * rad_diff + flat_radius
            if max_cutting_height > h:
                span_list.append([geom.Span(geom.Point(flat_radius, 0), geom.Vertex(geom.Point(radius_at_cutting_height, h)), False), GRAY])
                span_list.append([geom.Span(geom.Point(radius_at_cutting_height, h), geom.Vertex(geom.Point(r, max_cutting_height)), False), GRAY])
                span_list.append([geom.Span(geom.Point(r, max_cutting_height), geom.Vertex(geom.Point(r, max_cutting_height + height_above_cutting_edge)), False), RED])
            else:
                span_list.append([geom.Span(geom.Point(flat_radius, 0), geom.Vertex(geom.Point(r, max_cutting_height)), False), GRAY])
                span_list.append([geom.Span(geom.Point(r, max_cutting_height), geom.Vertex(geom.Point(r, h)), False), GRAY])
                span_list.append([geom.Span(geom.Point(r, h), geom.Vertex(geom.Point(r, h + height_above_cutting_edge)), False), RED])
    elif tool.type == TOOL_TYPE_ENDMILL or tool.type == TOOL_TYPE_SLOTCUTTER:
        span_list.append([geom.Span(geom.Point(r, 0), geom.Vertex(geom.Point(r, h)), False), GRAY])
        span_list.append([geom.Span(geom.Point(r, h), geom.Vertex(geom.Point(r, h + height_above_cutting_edge)), False), RED])
    elif tool.type == TOOL_TYPE_BALLENDMILL:
        if h > r:
            span_list.append([geom.Span(geom.Point(0, 0), geom.Vertex(1, geom.Point(r, r), geom.Point(0, r)), False), GRAY])
            span_list.append([geom.Span(geom.Point(r, r), geom.Vertex(geom.Point(r, h)), False), GRAY])
            span_list.append([geom.Span(geom.Point(r, h), geom.Vertex(geom.Point(r, h + height_above_cutting_edge)), False), RED])
        else:
            x = math.sqrt(r*r - (r-h) * (r-h))
            span_list.append([geom.Span(geom.Point(0, 0), geom.Vertex(1, geom.Point(x, h), geom.Point(0, r)), False), GRAY])
            span_list.append([geom.Span(geom.Point(x, h), geom.Vertex(1, geom.Point(r, r), geom.Point(0, r)), False), RED])
            span_list.append([geom.Span(geom.Point(r, r), geom.Vertex(geom.Point(r, r + height_above_cutting_edge)), False), RED])
    else:
        if cr > r: cr = r
        if cr > 0.0001:
            if h >= cr:
                span_list.append([geom.Span(geom.Point(r-cr, 0), geom.Vertex(1, geom.Point(r, cr), geom.Point(r-cr, cr)), False), GRAY])
                span_list.append([geom.Span(geom.Point(r, r), geom.Vertex(geom.Point(r, h)), False), GRAY])
                span_list.append([geom.Span(geom.Point(r, h), geom.Vertex(geom.Point(r, h + height_above_cutting_edge)), False), RED])
            else:
                x = (r - cr) + math.sqrt(cr*cr - (cr-h) * (cr-h))
                span_list.append([geom.Span(geom.Point(r-cr, 0), geom.Vertex(1, geom.Point(x, h), geom.Point(0, cr)), False), GRAY])
                span_list.append([geom.Span(geom.Point(x, h), geom.Vertex(1, geom.Point(r, cr), geom.Point(0, cr)), False), RED])
                span_list.append([geom.Span(geom.Point(r, cr), geom.Vertex(geom.Point(r, cr + height_above_cutting_edge)), False), RED])
        else:
            span_list.append([geom.Span(geom.Point(r, 0), geom.Vertex(geom.Point(r, h)), False), GRAY])
            span_list.append([geom.Span(geom.Point(r, h), geom.Vertex(geom.Point(r, h + height_above_cutting_edge)), False), RED])
    
    return Tool(span_list)

class Toolpath:
    def __init__(self):
        self.length = 0.0
        self.lines = []
        self.current_pos = 0.0
        self.current_point = Point(0, 0, 0)
        self.current_line_index = 0
        self.tools = {} # dictionary, tool id to Tool object
        self.current_tool = 1
        self.rapid = True
        self.mm_per_sec = 50.0
        self.running = False
        self.coords = Coords(0, 0, 0, 0, 0, 0)
        self.in_cut_to_position = False
        
    def add_line(self, p0, p1):
        self.lines.append(Line(p0, p1, self.rapid, self.current_tool))
        
    def Reset(self):
        global toolpath
        toolpath = self
        
        # get the box of all the solids
        box = wx.GetApp().program.stocks.GetBox()
        if box.valid:
            c = box.Center()
            width = box.Width()
            height = box.Height()
            depth = box.Depth() + 10
            minz = box.MinZ() - 10
            if width < 100: width = 100
            if height < 100: height = 100
            box.InsertBox(geom.Box3D(c.x - width/2, c.y - height/2, minz, c.x + width/2, c.y + height/2, minz + depth))
        else:
            box.InsertBox(geom.Box3D(-100, -100, -50, 100, 100, 50))
            
        self.coords = Coords(box.MinX(), box.MinY(), box.MinZ(), box.MaxX(), box.MaxY(), box.MaxZ())
        
        self.coorfs.add_block(0,0,-10,100,100,10)
        # add each stock
        stocks = wx.GetApp().program.stocks.GetChildren()
        for stock in stocks:
            stock_box = stock.GetBox()
            sim.set_current_color(stock.GetColor().ref())
            c = box.Center()
            self.coords.add_block(c.x, c.y, box.MinZ(), box.Width(), box.Height(), box.Depth())
            
        tools = wx.GetApp().program.tools.GetChildren()
        for tool in tools:
            self.tools[tool.tool_number] = GetSimToolDefinition(tool)
            
        machine_module = __import__('nc.' + wx.GetApp().program.machine.reader, fromlist = ['dummy'])
        parser = machine_module.Parser(self)
        parser.Parse(wx.GetApp().program.GetOutputFileName())
        self.rewind()
        
        self.timer = wx.Timer(wx.GetApp().frame, wx.ID_ANY)
        self.timer.Start(33)
        wx.GetApp().frame.Bind(wx.EVT_TIMER, OnTimer)
        
    def rewind(self):
        self.current_point = Point(0, 0, 0)
        if len(self.lines)>0:
            self.current_point = self.lines[0].p0
        self.current_pos = 0.0
        self.current_line_index = 0
        self.running = False
        
    def draw_tool(self):
        sim.drawclear()
        
        index = self.current_line_index - 1
        if index < 0: index = 0
        tool_number = self.lines[index].tool_number
        
        if tool_number in self.tools:
            x, y, z = self.coords.mm_to_voxels(self.current_point.x, self.current_point.y, self.current_point.z)
            self.tools[tool_number].draw(x, y, z)
        
    def cut_point(self, p):
        x, y, z = self.coords.mm_to_voxels(p.x, p.y, p.z)
        index = self.current_line_index - 1
        if index < 0: index = 0
        tool_number = self.lines[index].tool_number
        
        if tool_number in self.tools:
            self.tools[tool_number].cut(x, y, z)
         
    def cut_line(self, line):
#        self.cut_point(line.p0)
#        self.cut_point(line.p1)
#        sim.remove_line(int(line.p0.x), int(line.p0.y), int(line.p0.z), int(line.p1.x), int(line.p1.y), int(line.p1.z), 5)
        
        length = line.Length()
        num_segments = int(1 + length * self.coords.voxels_per_mm * 0.06)
        step = length/num_segments
        dv = (line.p1 - line.p0) * (1.0/num_segments)
        for i in range (0, num_segments + 1):
            p = line.p0 + (dv * i)
            self.cut_point(p)
            
    def cut_to_position(self, pos):
        if self.current_line_index >= len(self.lines):
            return
        
        if self.cut_to_position == True:
            import wx
            wx.MessageBox("in cut_to_position again!")
        
        self.in_cut_to_position = True
        start_pos = self.current_pos
        while self.current_line_index < len(self.lines):
            line = copy.copy(self.lines[self.current_line_index])
            line.p0 = self.current_point
            line_length = line.Length()
            if line_length > 0:
                end_pos = self.current_pos + line_length
                if pos < end_pos:
                    fraction = (pos - self.current_pos)/(end_pos - self.current_pos)
                    line.p1 = line.p0 + ((line.p1 - line.p0) * fraction)
                    self.cut_line(line)
                    self.current_pos = pos
                    self.current_point = line.p1
                    break
                self.cut_line(line)
                self.current_pos = end_pos
            self.current_point = line.p1
            self.current_line_index = self.current_line_index + 1
            
        self.in_cut_to_position = False
    
toolpath = Toolpath()
    
