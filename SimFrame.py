import sys
import os
import wx

sim_dir = os.path.dirname(os.path.realpath(__file__))
pycam_dir = os.path.realpath(sim_dir + '/../PyCAM')
sys.path.append(pycam_dir)

from CamFrame import CamFrame # from CAM
from SimControls import SimControls
from SimCanvas import SimCanvas
from Toolpath import Toolpath
import sim

class SimFrame(CamFrame):
    def __init__(self, parent, id=-1, pos=wx.DefaultPosition, size=wx.DefaultSize, style=wx.DEFAULT_FRAME_STYLE, name=wx.FrameNameStr):
        CamFrame.__init__(self, parent, id, pos, size, style, name)
        
    def AddExtraMenus(self):
        save_bitmap_path = self.bitmap_path
        self.bitmap_path = sim_dir + '/bitmaps'
        
        self.AddMenu('&Simulation')
        self.AddMenuItem('Simulate', self.OnSimulate, None, 'simulate')        
        self.EndMenu()      
        
        self.AddMenuItem('Simulation Controls', self.OnViewSimControls, self.OnUpdateViewSimControls, check_item = True, menu = self.window_menu)
        
        self.bitmap_path = save_bitmap_path
            
    def MakeGraphicsCanvas(self):
        return SimCanvas(self)

    def AddExtraWindows(self):
        self.sim_controls = SimControls(self)
        self.aui_manager.AddPane(self.sim_controls, wx.aui.AuiPaneInfo().Name('SimControls').Caption('Simulation Controls').Center().Bottom().BestSize(wx.Size(300, 80)))
        wx.GetApp().RegisterHideableWindow(self.sim_controls)
        
    def OnSimulate(self, e):
        wx.GetApp().toolpath = Toolpath()
        sim.drawline3d(-10,-10,-10,-10,-10,30,3453534)
        self.sim_controls.SetFromSimulation(wx.GetApp().toolpath)

    def OnViewSimControls(self, e):
        pane_info = self.aui_manager.GetPane(self.sim_controls)
        if pane_info.IsOk():
            pane_info.Show(e.IsChecked())
            self.aui_manager.Update()
        
    def OnUpdateViewSimControls(self, e):
        e.Check(self.aui_manager.GetPane(self.sim_controls).IsShown())
        
    def OnViewReset(self):
        sim.ViewReset()
        self.graphics_canvas.Refresh()
