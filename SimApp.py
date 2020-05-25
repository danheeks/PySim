import wx
import os
import sys

sim_dir = os.path.dirname(os.path.realpath(__file__))
pycam_dir = os.path.realpath(sim_dir + '/../PyCAM')
sys.path.append(pycam_dir)

from CamApp import CamApp # from CAD
from SimFrame import SimFrame
from Toolpath import Toolpath

import sim

class SimApp(CamApp):
    def __init__(self):
        self.sim_dir = sim_dir
        self.toolpath = None
        CamApp.__init__(self)

    def GetAppName(self):
        return 'Computer Aided Manufacturing with Solid Simulation'
    
    def NewFrame(self, pos=wx.DefaultPosition, size=wx.DefaultSize):
        return SimFrame(None, pos = pos, size = size)
