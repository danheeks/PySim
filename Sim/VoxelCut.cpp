// Just flying over VXL map
// by Tom Dobrowolski 2003-04-08

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <list>
#include "sysmain.h"
#include "voxlap5.h"

#include <fstream>
using namespace std;

extern void get_canvas_camera(dpoint3d &ipos, dpoint3d &istr, dpoint3d &ihei, dpoint3d &ifor);

const char* Ttc(const wchar_t* str);
const wchar_t* Ctt(const char* str);

//Player position variables:
#define NOCLIPRAD 7
#define CLIPRAD 5
#define CLIPVEL 8.0
#define MINVEL 0.5
dpoint3d ipos, istr, ihei, ifor, ivel, ivelang;


struct draw_point
{
	float x, y, z;
};

std::list<draw_point> points_to_draw;

extern void draw_callback();

long initapp (long argc, char **argv)
{
	char *level = NULL;
	
	xres = 1024; yres = 768; colbits = 32; fullscreen = 0;

	initvoxlap();

	vx5.maxscandist = 2048;
	vx5.fogcol = 0x808080;
	vx5.lightmode = 1;
	vx5.curcol = 0x808080;
	setsideshades(0,4,1,3,2,2);
// load a default scene
	loadnul (&ipos,&istr,&ihei,&ifor);

	// remove all voxels
	{
		lpoint3d pmin, pmax;
		pmin.x = 0; pmin.y = 0; pmin.z = 0;
		pmax.x = 1023; pmax.y = 1023; pmax.z = 1023;
		setrect(&pmin, &pmax, -1);
	}
	updatevxl();
	
	vx5.fallcheck = 1;

	ivel.x = ivel.y = ivel.z = 0;
	ivelang.x = ivelang.y = ivelang.z = 0;
	
	return(0);
}

void uninitapp ()
{
	uninitvoxlap();
}
	 
static float fov = 0.6f;

void doframe ()
{
	long frameptr, pitch, xdim, ydim;
	
//	if (startdirectdraw(&frameptr,&pitch,&xdim,&ydim)) {
		voxsetframebuffer(frameptr,pitch,xdim,ydim);

		get_canvas_camera(ipos, istr, ihei, ifor);

		setcamera(&ipos,&istr,&ihei,&ifor,xres*.5f,yres*.5f,xres*fov); // .5f
		
		opticast();

		draw_callback();

//		stopdirectdraw();
//		nextpage();
//	}
}

