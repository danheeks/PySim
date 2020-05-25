import wx
from GraphicsCanvas import GraphicsCanvas
import sim
import Mouse

class SimCanvas(GraphicsCanvas):
    def __init__(self, parent):
        GraphicsCanvas.__init__(self, parent)
        sim.Init(0)

    def Resize(self):
      s = self.GetClientSize()
      print('s = ' + str(s))
      sim.OnSize(s.Width, s.Height)
      GraphicsCanvas.Resize(self)

    def OnMouse(self, event):
        if wx.GetApp().toolpath == None:
            GraphicsCanvas.OnMouse(self, event)
        else:
            e = Mouse.MouseEventFromWx(event)
            sim.OnMouse(e)
            if sim.refresh_wanted() == True:
                self.Refresh()
            event.Skip()
        
    def OnPaint(self, event):
        if wx.GetApp().toolpath == None:
            pass
            #GraphicsCanvas.OnPaint(self, event)
        else:
            dc = wx.PaintDC(self)
            self.SetCurrent(self.context)
            sim.OnPaint()
            self.SwapBuffers()
