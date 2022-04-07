version "2.4"

class CameraHandler : StaticEventHandler
{
	static const int DamageToAlpha[] =
	{
		  0,   8,  16,  23,  30,  36,  42,  47,  53,  58,  62,  67,  71,  75,  79,
		 83,  87,  90,  94,  97, 100, 103, 107, 109, 112, 115, 118, 120, 123, 125,
		128, 130, 133, 135, 137, 139, 141, 143, 145, 147, 149, 151, 153, 155, 157,
		159, 160, 162, 164, 165, 167, 169, 170, 172, 173, 175, 176, 178, 179, 181,
		182, 183, 185, 186, 187, 189, 190, 191, 192, 194, 195, 196, 197, 198, 200,
		201, 202, 203, 204, 205, 206, 207, 209, 210, 211, 212, 213, 214, 215, 216,
		217, 218, 219, 220, 221, 221, 222, 223, 224, 225, 226, 227, 228, 229, 229,
		230, 231, 232, 233, 234, 235, 235, 236, 237
	};
	
	private ThirdPersonCamera cam;
	private bool bThirdPerson;
	private Color poisonColor;
	private Color hazardColor;
	private Color bonusColor;
	private Color iceColor;
	private Color invColor;
	private Color damageColor;
	private double maxAlpha;
	
	override void OnRegister()
	{
		poisonColor = Color(10, 66, 0);
		hazardColor = Color(0, 66, 0);
		bonusColor = Color(215, 186, 69);
		iceColor = Color(102, 64, 64, 218);
		
		maxAlpha = 0.5;
	}
	
	override void WorldLoaded(WorldEvent e)
	{
		let it = ThinkerIterator.Create("ThirdPersonCamera", Thinker.MAX_STATNUM);
		cam = ThirdPersonCamera(it.Next());
		if (!cam)
			cam = ThirdPersonCamera(Actor.Spawn("ThirdPersonCamera", players[consoleplayer].mo.pos));
		
		cam.Init(bThirdPerson);
	}
	
	// These only need to be updated once per tick
	override void WorldTick()
	{
		maxAlpha = 0.5;
		
		Color newInvColor;
		for (let i = players[consoleplayer].mo.inv; i; i = i.inv)
		{
			Color ic = i.GetBlend(); // Why is this not clearscope ??
			if (ic.a)
			{
				newInvColor = AddBlend(ic, newInvColor);
				if (ic.a/255. > maxAlpha)
					maxAlpha = ic.a / 255.;
			}
		}
		
		invColor = newInvColor;
		
		Color newDamageColor;
		if (players[consoleplayer].damageCount)
		{
			Color pain = players[consoleplayer].mo.GetPainFlash();
			int cnt = DamageToAlpha[min(players[consoleplayer].damageCount * pain.a/255., 113)] * blood_fade_scalar;
			if (cnt)
			{
				if (cnt > 175)
					cnt = 175;
				
				newDamageColor = Color(cnt, pain.r, pain.g, pain.b);
			}
		}
		
		damageColor = newDamageColor;
	}
	
	override void RenderUnderlay(RenderEvent e)
	{
		if (automapactive)
			return;
		
		// Attempt to add at least some screen blending
		let cam = ThirdPersonCamera(players[consoleplayer].camera);
		if (cam)
		{
			Color output;
			if (invColor.a)
				output = invColor;
			
			if (players[consoleplayer].bonusCount)
			{
				int cnt = min((players[consoleplayer].bonusCount << 3) * pickup_fade_scalar, 128);
				output = AddBlend(Color(cnt, bonusColor.r, bonusColor.g, bonusColor.b), output);
			}
			
			if (damageColor.a)
				output = AddBlend(damageColor, output);
			
			if (players[consoleplayer].poisonCount)
			{
				int cnt = (min(players[consoleplayer].poisonCount, 64) / 93.2571428571) * 255;
				output = AddBlend(Color(cnt, poisonColor.r, poisonColor.g, poisonColor.b), output);
			}
			
			if (players[consoleplayer].hazardCount)
			{
				int cnt = (min(players[consoleplayer].hazardCount >> 3, 64) / 93.2571428571) * 255;
				output = AddBlend(Color(cnt, hazardColor.r, hazardColor.g, hazardColor.b), output);
			}
			
			if (players[consoleplayer].mo.DamageType == 'Ice')
				output = AddBlend(iceColor, output);
			
			if (output.a)
			{
				int x, y, w, h;
				[x, y, w, h] = Screen.GetViewWindow();
				
				double alpha = output.a / 255.;
				if (alpha > maxAlpha)
					alpha = maxAlpha;
				
				Screen.Dim(output, alpha, x, y, w, h);
			}
		}
	}
	
	private clearscope Color AddBlend(Color c, Color blend)
	{
		if (c.a <= 0)
			return blend;
		
		double a2 = (blend.a + (1-(blend.a/255.))*c.a) / 255.;
		double a3 = (blend.a/255.) / a2;
		
		int cr = blend.r*a3 + c.r*(1-a3);
		int cg = blend.g*a3 + c.g*(1-a3);
		int cb = blend.g*a3 + c.b*(1-a3);
		int ca = a2*255;
		
		return Color(ca, cr, cg, cb);
	}
	
	// These have to be changed from the playsim which is why ConsoleProcess isn't used
	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.player != consoleplayer)
			return;
		
		if (e.name ~== "ToggleCamera")
		{
			bThirdPerson = !bThirdPerson;
			cam.ToggleThirdPerson(bThirdPerson);
		}
	}
}

class CameraHitData
{
	Line hitLine;
	double hitDistance;
	Vector2 hitPos;
}

class CameraTracer : LineTracer
{
	bool bHitPortal;
	Array<CameraHitData> hits;
	
	override ETraceStatus TraceCallback()
	{
		switch (results.hitType)
		{
			case TRACE_CrossingPortal:
				bHitPortal = true;
				results.hitType = TRACE_HitNone;
				break;
				
			case TRACE_HitWall:
				if (!(results.hitLine.flags & Line.ML_BLOCKEVERYTHING) &&
					(results.hitLine.flags & Line.ML_TWOSIDED) &&
					results.tier == TIER_Middle)
				{
					let chd = new("CameraHitData");
					chd.hitLine = results.hitLine;
					chd.hitDistance = results.distance;
					chd.hitPos = results.hitPos.xy;
					hits.Push(chd);
					
					break;
				}
			case TRACE_HitFloor:
			case TRACE_HitCeiling:
				if (results.ffloor
					&& (!(results.ffloor.flags & F3DFloor.FF_EXISTS)
					|| !(results.ffloor.flags & F3DFloor.FF_SOLID)))
				{
					results.ffloor = null;
					break;
				}
				return TRACE_Stop;
		}
		
		return TRACE_Skip;
	}
}

class ThirdPersonCamera : Actor
{
	const DEFAULT_DISTANCE = 16.;
	const DEFAULT_HEIGHT = 28.;
	
	private transient CVar camDist;
	private transient CVar camHeight;
	
	private bool bThirdPerson;
	private double prevAng;
	private bool prevPortal;
	
	Default
	{
		FloatBobPhase 0;
		Radius 0;
		Height 0;
		
		+SYNCHRONIZED
		+NOBLOCKMAP
		+NOSECTOR
	}
	
	void Init(bool toggle)
	{
		ToggleThirdPerson(toggle);
		prevAng = angle = players[consoleplayer].mo.angle;
		pitch = players[consoleplayer].mo.pitch;
		roll = players[consoleplayer].mo.roll;
		cameraFOV = players[consoleplayer].FOV;
		prevPortal = false;
	}
	
	void ToggleThirdPerson(bool toggle)
	{
		bThirdPerson = toggle;
		if (!bThirdPerson && players[consoleplayer].camera == self)
			players[consoleplayer].camera = players[consoleplayer].mo;
	}
	
	override void BeginPlay()
	{
		super.BeginPlay();
		
		ChangeStatNum(MAX_STATNUM);
	}
	
	override void Tick()
	{
		let p = players[consoleplayer].mo;
		cameraFOV = players[consoleplayer].FOV;
		pitch = p.pitch;
		roll = p.roll;
		
		if (!bThirdPerson || (players[consoleplayer].camera != self && players[consoleplayer].camera != p))
		{
			prevAng = angle = p.angle;
			prevPortal = false;
			p.spriteAngle = 0;
			p.bSpriteAngle = false;
			return;
		}
		
		players[consoleplayer].camera = self;
		players[consoleplayer].cheats &= ~CF_CHASECAM;
		p.bSpriteAngle = true;
		
		let tracer = new("CameraTracer");
		if (!tracer)
			return;
		
		if (!camDist)
			camDist = CVar.GetCVar("tp_camdistance", players[consoleplayer]);
		if (!camHeight)
			camHeight = CVar.GetCVar("tp_camheight", players[consoleplayer]);
		
		Vector3 dir = (AngleToVector(p.angle+180, cos(-pitch)), sin(pitch));
		double dist = p.radius;
		if (dist ~== 0)
			dist = DEFAULT_DISTANCE;
		dist += camDist.GetFloat();
		
		double zOfs = p.height / 2;
		if (zOfs ~== 0)
			zOfs = DEFAULT_HEIGHT;
		zOfs += (camHeight.GetFloat() - p.floorclip);
		
		bool hit = tracer.Trace(p.pos+(0,0,zOfs), p.CurSector, dir, dist, TRACE_ReportPortals);
		double length = hit ? tracer.results.distance : dist;
		for (uint i = 0; i < tracer.hits.Size(); ++i)
		{
			Line l = tracer.hits[i].hitLine;
			TextureID front = l.sidedef[0].GetTexture(Side.mid);
			TextureID back = l.sidedef[1].GetTexture(Side.mid);
			
			bool validFront = front.IsValid();
			bool validBack = back.IsValid();
				
			if (validFront ^ validBack)
			{
				Vector2 hitPos = tracer.hits[i].hitPos;
				Sector frontSec = l.frontsector;
				Sector backSec = l.backsector;
				
				double fDelta = frontSec.ceilingPlane.ZatPoint(hitPos) - frontSec.floorPlane.ZatPoint(hitPos);
				double bDelta = backSec.ceilingPlane.ZatPoint(hitPos) - backSec.floorPlane.ZatPoint(hitPos);
				
				Vector2 size;
				if (validFront)
					size = TexMan.GetScaledSize(front);
				else
					size = TexMan.GetScaledSize(back);
				
				if (size.y >= fDelta || size.y >= bDelta)
				{
					hit = true;
					length = tracer.hits[i].hitDistance;
					break;
				}
			}
		}
		
		if (hit)
			length = max(0, length-1);
		
		Vector3 ofs = (0,0,zOfs) + dir*length;
		SetOrigin(p.Vec3Offset(ofs.x, ofs.y, ofs.z), true);
		
		if (pos.z < floorZ)
			SetZ(floorZ);
		else if (pos.z + height > ceilingZ)
			SetZ(ceilingZ - height);
		
		angle = abs(dir.z) < 1 ? tracer.results.SrcAngleFromTarget + 180 : p.angle;
		if (p.player.attackDown)
			p.spriteAngle = 0;
		else
		{
			if (p.player.cmd.forwardMove || p.player.cmd.sideMove)
				p.spriteAngle = atan2(p.player.cmd.sideMove, p.player.cmd.forwardMove);
			else if (!(tracer.bHitPortal ^ prevPortal))
				p.spriteAngle += DeltaAngle(prevAng, angle);
		}
		
		prevAng = angle;
		prevPortal = tracer.bHitPortal;
	}
}