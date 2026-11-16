# Copilot/Guest property update (passive observation) by Tomaskom
# This script handles copying over properties to the local tree for use in passenger or copilot over MP

#property holding/reporting current host to copy from
#empty string stored means no current host
var hostMpProp = "/copilot/host-MP-path";
props.globals.initNode(hostMpProp, "", "STRING");

#array holding node pair objects for subtree copy
var copySubtrees = [];

#array holding path pair objects for value copy (is executed after subtrees)
var copyValues = [];


#class holding node pairs for subtree copy
var Subtree = {
	new: func(readPath, writePath) {
		var m = { parents: [Subtree] };
		m.readNode = props.globals.getNode(readPath);
		m.writeNode = props.globals.getNode(writePath);
		append(copySubtrees, m);
		return m;
	},
	copy: func {
		if(me.readNode==nil or me.writeNode==nil) return;
		props.copy(me.readNode, me.writeNode);
	},
};

#class holding path pairs for value copy
var Value = {
	new: func(readPath, writePath, type=nil) {
		var m = { parents: [Value] };
		var val = getprop(readPath);
		if(type!=nil and val!=nil) props.globals.initNode(writePath, val, type);
		else if(val!=nil) setprop(writePath, val);
		m.readPath = readPath;
		m.writePath = writePath;
		append(copyValues, m);
		return m;
	},
	copy: func {
		var val = getprop(me.readPath);
		if(val==nil) return;
		setprop(me.writePath, val);
	},
};


#array with MP int indexes to copy
var mpInts = [0,1,2,3,4,5,6,7,8];
#array with MP float indexes to copy
var mpFloats = [0,1,2,3,4,5];
#array with MP string indexes to copy
var mpStrings = [];


var listenTargetHide = nil;
var recentTarg = nil;

var setNodes = func {
	if(listenTargetHide!=nil) {
		removelistener(listenTargetHide);
		listenTargetHide = nil;
	}
	
	var targ = getprop(hostMpProp);
	
	if(targ=="" or targ==nil) {
		if(recentTarg!=nil) setprop(recentTarg~"/copilot/hide-me", 0);
		setprop("/copilot/hide-me", 1);
		recentTarg = targ;
		copySubtrees = [];
		copyValues = [];
		listenTargetHide = nil;
		return;
	}
	
	setprop("/copilot/hide-me", 0);
	#via listener, because the host aircraft may not be loaded due to large distance and the value would be overridden when loaded
	listenTargetHide = setlistener(targ~"/copilot/hide-me", func {setprop(targ~"/copilot/hide-me", 1);}, 1, 0);
	
	#Subtree.new(targ~"/position", "/position");
	#Subtree.new(targ~"/orientation", "/orientation");
	Subtree.new(targ~"/velocities", "/velocities");
	Subtree.new(targ~"/canopy", "/canopy");
	Subtree.new(targ~"/engines/engine[0]", "/engines/engine[0]");
	Subtree.new(targ~"/gear", "/gear");
	Subtree.new(targ~"/controls/lighting", "/controls/lighting");
	Subtree.new(targ~"/surface-positions", "/surface-positions");
	#Subtree.new(targ~"/disintegration", "/disintegration");
	Subtree.new(targ~"/sim/model/livery", "/sim/model/livery");
	
	Value.new(targ~"/position/altitude-ft", "/position/altitude-ft");
	Value.new(targ~"/position/latitude-deg", "/position/latitude-deg");
	Value.new(targ~"/position/longitude-deg", "/position/longitude-deg");
	Value.new(targ~"/orientation/true-heading-deg", "/orientation/heading-deg");
	Value.new(targ~"/orientation/pitch-deg", "/orientation/pitch-deg");
	Value.new(targ~"/orientation/roll-deg", "/orientation/roll-deg");
	#Value.new(targ~"/velocities/true-airspeed-kt", "/velocities/airspeed-kt");
	
	
	recentTarg = targ;
}

var update = func {
	var targ = getprop(hostMpProp);
	if(targ=="" or targ==nil) {
		copySubtrees = [];
		copyValues = [];
		return;
	}
	
	
	foreach(var subtr; copySubtrees) {
		subtr.copy();
	}
	
	foreach(var mpI; mpInts) {
		var val = getprop(targ~"/sim/multiplay/generic/int["~mpI~"]");
		if(val!=nil) setprop("/sim/multiplay/generic/int["~mpI~"]", val);
	}
	
	foreach(var mpF; mpFloats) {
		var val = getprop(targ~"/sim/multiplay/generic/float["~mpF~"]");
		if(val!=nil) setprop("/sim/multiplay/generic/float["~mpF~"]", val);
	}
	
	foreach(var mpS; mpStrings) {
		var val = getprop(targ~"/sim/multiplay/generic/string["~mpS~"]");
		if(val!=nil) setprop("/sim/multiplay/generic/string["~mpS~"]", val);
	}
	
	foreach(var val; copyValues) {
		val.copy();
	}
	
	#velocity, processed from KTAS to KIAS (rough approximation of inverted aircraft.kias_to_ktas())
	var seapress = getprop("/environment/pressure-sea-level-inhg");
	var seatemp = getprop("/environment/temperature-sea-level-degc");
	var coralt_ft = getprop(targ~"/position/altitude-ft") + (29.92 - seapress) * 910;
	var ktas = abs(getprop(targ~"/velocities/true-airspeed-kt") + aircraft.wind_speed_from(getprop(targ~"/orientation/true-heading-deg")));
	var kias = ktas / (1 + 0.00232848233 * (seatemp - 15))
			/ (1.0025 + coralt_ft * (0.0000153
			- ktas * (coralt_ft * 0.0000000000003 + 0.0000000045)
			+ (0.0000119 * (math.exp(coralt_ft * 0.000016) - 1))));
	setprop("/velocities/airspeed-kt", kias);
	
	#payload info
	forindex(var iNode; props.globals.getNode(targ~"/sim").getChildren("weight")) {
		var id = getprop(targ~"/sim/weight["~iNode~"]/payload-int");
		if(id!=nil) setprop("/sim/weight["~iNode~"]/payload-int", id);
	}

	var crashed = getprop(targ~"/sim/crashed");
	if(crashed!=nil and crashed!=getprop("/sim/crashed")) setprop("/sim/crashed", crashed); #if work-around to prevent Bombable from picking up writes
	
	#AGL calculation - can be disabled to improve performance
	var geoI = geodinfo(getprop(targ~"/position/latitude-deg"), getprop(targ~"/position/longitude-deg"));
	var alt = getprop(targ~"/position/altitude-ft");
	if(geoI!=nil and alt!=nil) setprop("/position/altitude-agl-ft", alt-M2FT*geoI[0]);
	
}


var listenFrame_Instructor = setlistener("/sim/signals/frame", update, 1, 1);
var listenTargChange_Instructor = setlistener(hostMpProp, setNodes, 1, 1);

print("L-159 dual controls local model updates code initialized");



