import com.GameInterface.DistributedValue;
import com.GameInterface.Game.Character;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Nametags;
import com.GameInterface.Waypoint;
import com.GameInterface.WaypointInterface;
import com.Utils.Archive;
import com.Utils.ID32;
import com.xeio.MobMarkers.Utils;
import flash.geom.Point;
import mx.utils.Delegate;

class MobMarkers
{    
    private var m_swfRoot: MovieClip;
    private var m_dynels:Array;
    private var m_screenWidth:Number;
    private var m_playfields:Array;

    private var m_zonesCommand:DistributedValue;
    private var m_addZoneCommand:DistributedValue;
    private var m_removeZoneCommand:DistributedValue;
    
    public static function main(swfRoot:MovieClip):Void 
    {
        var MobMarkers = new MobMarkers(swfRoot);

        swfRoot.onLoad = function() { MobMarkers.OnLoad(); };
        swfRoot.OnUnload = function() { MobMarkers.OnUnload(); };
        swfRoot.OnModuleActivated = function(config:Archive) { MobMarkers.Activate(config); };
        swfRoot.OnModuleDeactivated = function() { return MobMarkers.Deactivate(); };
    }

    public function MobMarkers(swfRoot: MovieClip) 
    {
        m_swfRoot = swfRoot;
    }

    public function OnUnload()
    {
        m_swfRoot.onEnterFrame = undefined;
        
		Nametags.SignalNametagAdded.Disconnect(Add, this);
        Nametags.SignalNametagRemoved.Disconnect(Add, this);
        Nametags.SignalNametagUpdated.Disconnect(Add, this);
        
        WaypointInterface.SignalPlayfieldChanged.Disconnect(PlayFieldChanged, this);
        
        m_zonesCommand.SignalChanged.Disconnect(ParseZoneIds, this);
        m_zonesCommand = undefined;
        
        m_addZoneCommand.SignalChanged.Disconnect(AddZone, this);
        m_addZoneCommand = undefined;
        
        m_removeZoneCommand.SignalChanged.Disconnect(RemoveZone, this);
        m_removeZoneCommand = undefined;
        
        for (var i in m_dynels)
        {
            Remove(m_dynels[i]);
        }
    }

    public function Activate(config: Archive)
    {
    }

    public function Deactivate(): Archive
    {
        var archive: Archive = new Archive();			
        return archive;
    }

    public function OnLoad()
    {
        m_zonesCommand = DistributedValue.Create("MobMarkers_Zones");
        m_zonesCommand.SignalChanged.Connect(ParseZoneIds, this);
        
        m_addZoneCommand = DistributedValue.Create("MobMarkers_AddZone");
        m_addZoneCommand.SignalChanged.Connect(AddZone, this);
        
        m_removeZoneCommand = DistributedValue.Create("MobMarkers_RemoveZone");
        m_removeZoneCommand.SignalChanged.Connect(RemoveZone, this);
        
        ParseZoneIds();
        
        m_dynels = [];
        m_swfRoot.onEnterFrame = Delegate.create(this, OnFrame);
        
        m_screenWidth = Stage["visibleRect"].width;
        
        Nametags.SignalNametagAdded.Connect(Add, this);
        Nametags.SignalNametagRemoved.Connect(Add, this);
        Nametags.SignalNametagUpdated.Connect(Add, this);
        
        Nametags.RefreshNametags();
        
        WaypointInterface.SignalPlayfieldChanged.Connect(PlayFieldChanged, this);
    }
    
    private function OnFrame()
    {
        for (var i in m_dynels)
        {
			var dynel:Dynel = m_dynels[i];
			if (!ShouldWatch(dynel))
            {
				Remove(dynel);
				return;
			}
            
            var waypoint/*:ScreenWaypoint*/ = _root.waypoints.m_RenderedWaypoints[dynel.GetID()];
            waypoint.m_Waypoint.m_DistanceToCam = dynel.GetCameraDistance();
			var screenPosition:Point = dynel.GetScreenPosition();
			waypoint.m_Waypoint.m_ScreenPositionX = screenPosition.x;
			waypoint.m_Waypoint.m_ScreenPositionY = screenPosition.y;
			waypoint.Update(m_screenWidth);
			waypoint = undefined;
		}
    }
    
    private function Add(id:ID32)
    {
        if (!EnabledPlayfield()) return;
        
        var dynel:Dynel = Dynel.GetDynel(id);
        if (Utils.Contains(m_dynels, dynel)) return; //Already tracking
        
        if (ShouldWatch(dynel))
        {            
            var waypoint:Waypoint = new Waypoint();
			waypoint.m_WaypointType = _global.Enums.WaypointType.e_RMWPScannerBlip;
			waypoint.m_WaypointState = _global.Enums.QuestWaypointState.e_WPStateActive;
			waypoint.m_IsScreenWaypoint = true;
			waypoint.m_IsStackingWaypoint = true;
			waypoint.m_Radius = 0;
			waypoint.m_Color = 0xFF0000;
			waypoint.m_CollisionOffsetX = 0;
			waypoint.m_CollisionOffsetY = 0;
			waypoint.m_MinViewDistance = 0;
			waypoint.m_MaxViewDistance = 500;
			waypoint.m_Id = dynel.GetID();
			waypoint.m_Label = dynel.GetName();
			waypoint.m_WorldPosition = dynel.GetPosition();
			var screenPosition:Point = dynel.GetScreenPosition();
			waypoint.m_ScreenPositionX = screenPosition.x;
			waypoint.m_ScreenPositionY = screenPosition.y;
			waypoint.m_DistanceToCam = dynel.GetCameraDistance();
            
			_root.waypoints.m_CurrentPFInterface.m_Waypoints[dynel.GetID().toString()] = waypoint;
			_root.waypoints.m_CurrentPFInterface.SignalWaypointAdded.Emit(waypoint.m_Id);
            
            m_dynels.push(dynel);
        }
    }
    
    private function Remove(dynel:Dynel)
    {
        Utils.Remove(m_dynels, dynel);
        delete _root.waypoints.m_CurrentPFInterface.m_Waypoints[dynel.GetID().toString()];
        _root.waypoints.m_CurrentPFInterface.SignalWaypointRemoved.Emit(dynel.GetID());
    }
    
    private function ShouldWatch(dynel:Dynel): Boolean
    {
        return dynel.IsEnemy() && !dynel.IsDead();
    }
    
    private function EnabledPlayfield(): Boolean
    {
        return Utils.Contains(m_playfields, Character.GetClientCharacter().GetPlayfieldID());
    }
    
    private function PlayFieldChanged()
    {
        m_dynels = [];
    }
    
    private function ParseZoneIds()
    {
        m_playfields = [];
        var zoneString:String = m_zonesCommand.GetValue().toString();
        var zoneStringArray:Array = zoneString.split(",");
        for (var x in zoneStringArray)
        {
            m_playfields.push(parseInt(zoneStringArray[x]));
        }
    }
    
    private function AddZone()
    {
        if (m_addZoneCommand.GetValue() == undefined) return;
        
        if (!Utils.Contains(m_playfields, m_addZoneCommand.GetValue()))
        {
            m_playfields.push(m_addZoneCommand.GetValue());
            m_zonesCommand.SetValue(m_playfields.join(","));
            m_addZoneCommand.SetValue(undefined);
        }
    }
    
    private function RemoveZone()
    {
        if (m_removeZoneCommand.GetValue() == undefined) return;
        
        Utils.Remove(m_playfields, m_removeZoneCommand.GetValue());
        m_zonesCommand.SetValue(m_playfields.join(","));
        m_removeZoneCommand.SetValue(undefined);
    }
}
