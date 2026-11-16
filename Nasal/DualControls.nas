# Dual controls by Tomaskom
# This script is supposed to be embedded in all guest and host aircraft involved in the dual controls or passive observation.
# It repsesents a single point of configuration for all controls transmission/receiving setup.
#
# The code actually run is selected by detecting which host/guest aircraft this is; this is to prevent scattering of configuration
# on many places or having to keep the same bindings on the transmitting/receiving side. 
#
# The only things you need to configure are:
# -the handshakeString variable, determining which MP transferred string is used for commuticating the handshake
# -the hostId variable, representing the host model id string from /sim/model/path
# -the Position class instances (with name and id string) and relevant controlBind() calls to create a new position in the aircraft
#  and assign control properties to pair with transport properties (in case transp needs to be initialized, add the node type)
#
# This only represents the guest position description with controls transmission bindings (which are optional, you can have passive positions too). 
# However the receiving and mirroring of MP the variables (lat/lon/alt position, orientation, surface positions etc.) by the guests
# for correct model animation is separate, in the file DualControls_GuestUpdates.nas
# This also depends on the script DualControls_GUI.nas which handles request submission GUI, request queue, request accept GUI and more. 


var handshakeString = "/sim/multiplay/generic/string[1]";
props.globals.initNode(handshakeString, "", "STRING");

var hostId = "Aircraft/L-159/Models/L-159.xml";
var thisId = getprop("/sim/model/path");


#class holding a single request info (for submission to GUI)
var Request = {
	new: func(callsign, position, listenValidPath, callbackConfirm, mpIndex, meRef) {
		var m = { parents: [Request] };
		m.valid = 1;
		m.callsign = callsign;
		m.position = position;
		m.callbackConfirm = callbackConfirm;
		m.listenValidPath = listenValidPath;
		m.mpIndex = mpIndex;
		m.meRef = meRef;
		m.listenValid = setlistener(listenValidPath, func{m.valid=0;}, 0, 0);
		return m;
	},
	delListener: func {
		if(me.listenValid!=nil) removelistener(me.listenValid);
		me.listenValid = nil;
	},
};


#function that assembles handshakeString
var assembleHandshakeString = func {
	var positions = props.globals.getNode("/copilot/onboard/").getChildren();
	var str = "";
	foreach(var pos; positions) {
		var callsign = pos.getValue();
		if(callsign!=nil or callsign!="") str = str ~ pos.getName() ~ ":" ~ callsign ~ ",";
	}
	setprop(handshakeString, str);
}



#class representing an available MP position in aircraft
var Position = {
	new: func(name, id) {
		var m = { parents: [Position] };
		m.name = name;
		m.id = id;
		m.bindings = [];
		if(streq(hostId, thisId)) {
			#Host aircraft (receiving mode)
			props.globals.initNode("/copilot/ignore-requests", 0, "BOOL"); 
			props.globals.initNode("/copilot/two-way-sync", 1, "BOOL"); 
			m.knownMP = -1;
			m.listenMpHandshakes = [];
			props.globals.initNode("/copilot/onboard/"~m.name, "", "STRING");
			props.globals.initNode("/copilot/accept-controls/"~m.name, 1, "BOOL");
			setlistener("/copilot/onboard/"~m.name, assembleHandshakeString);
			m.onBoardListeners = {mp:nil, valid:nil, local:nil, frame:nil};
			m.listenNewMP = setlistener("/ai/models/num-players", func{m.handleNewMP()}, 1, 0);
			#m.listenTransmit = setlistener("/sim/signals/frame", func{m.transmitControlsHost();});
		}
		else if(streq(id, thisId)) {
			#Copilot/Passanger (guest, transmitting mode)
			props.globals.initNode("/copilot/host-MP-path-request", "", "STRING");
			m.listenHostReq = nil;
			setlistener("/copilot/host-MP-path-request", func{m.handleHostReq()}, 0, 1);
			m.listenOnboard = nil;
			m.listenHost = nil;
		}
		return m;
	},
	
	#adds a new pair of control property and used transmission property
	controlBind: func(controlProp, transProp, type=nil) {
		#control is the control input, trans is the property used for transport
		append(me.bindings, {control:controlProp, trans:transProp, listenerIn:nil, listenerOut:nil, timer:maketimer(5, func{me.forceReceiveControlsGuest();})});
		me.bindings[-1].timer.singleShot = 1;
		if(type!=nil) props.globals.initNode(transProp, 0, type);
	},
	
	##############################
	### Guest handling methods ###
	##############################
	
	#handles request sending when I'm the guest side
	handleHostReq: func {
		var req = getprop("/copilot/host-MP-path-request");
		if(req==nil or req=="") {
			if(me.listenHostReq!=nil) removelistener(me.listenHostReq);
			me.listenHostReq = nil;
			return;
		}
		if(me.listenHostReq!=nil) removelistener(me.listenHostReq);
		screen.log.write("Request for position "~me.name~" sent to "~getprop(req~"/callsign"));
		me.listenHostReq = setlistener(req~handshakeString, func{me.confirmHostReqCheck(req);}, 0, 0);
		me.confirmHostReqCheck(req); #can't use auto execute upon construction from setlistener, because removing the listener would fail
		setprop(handshakeString, me.name~":"~getprop(req~"/callsign"));
		
	},
	
	#checks for confirmation of my request when I'm the guest side
	confirmHostReqCheck: func(req) {
		var str = getprop(req~handshakeString);
		if(str==nil) return;
		var positions = split(",", str);
		foreach(var pos; positions) {
			var posSplit = split(":", pos);
			if( size(posSplit)==2 and streq(posSplit[0], me.name) and streq(posSplit[1], getprop("/sim/multiplay/callsign")) ) {
				removelistener(me.listenHostReq);
				me.listenHostReq = nil;
				screen.log.write(getprop(req~"/callsign")~" accepted your request for position "~me.name);
				setprop("/copilot/host-MP-path", req);
				me.listenOnboard = setlistener(req~handshakeString, func{me.hostCheck(req);}, 0, 0);
				me.listenHost = setlistener("/copilot/host-MP-path", func{me.hostCheck(req, 1);}, 0, 0);
				#start sync
				me.receiveControlsGuest(props.globals.getNode(req).getIndex());
				me.transmitControlsGuest();
			}
		}
	},
	
	#checks whether I'm still on board (leave==1 means I want to leave)
	hostCheck: func(req, leave=0) {
		if(leave or getprop("/copilot/host-MP-path")=="") {
			removelistener(me.listenOnboard);
			removelistener(me.listenHost);
			me.listenOnboard = nil;
			me.listenHost = nil;
			setprop("/copilot/host-MP-path-request", "");
			setprop("/copilot/host-MP-path", "");
			setprop(handshakeString, "");
			me.stopReceiveControlsGuest();
			me.stopTransmitControlsGuest();
			screen.log.write("You have left "~getprop(req~"/callsign")~" from position "~me.name);
		}
		
		var onBoard = 0;
		
		var str = getprop(req~handshakeString);
		if(str==nil) return;
		var positions = split(",", str);
		foreach(var pos; positions) {
			var posSplit = split(":", pos);
			if( size(posSplit)==2 and streq(posSplit[0], me.name) and streq(posSplit[1], getprop("/sim/multiplay/callsign")) ) {
				onBoard = 1;
			}
		}
		
		if(onBoard==0) {
			removelistener(me.listenOnboard);
			removelistener(me.listenHost);
			me.listenOnboard = nil;
			me.listenHost = nil;
			setprop("/copilot/host-MP-path-request", "");
			setprop("/copilot/host-MP-path", "");
			setprop(handshakeString, "");
			setprop(DualControls_GUI.pickHost_dialog.basenode.getNode("host-callsign").getPath(), "");
			me.stopReceiveControlsGuest();
			me.stopTransmitControlsGuest();
			screen.log.write(getprop(req~"/callsign")~" removed you from position "~me.name);
		}
		
	},
	
	#transmits controls by copying them to specified transfer properties
	transmitControlsGuest: func {
		foreach(var b; me.bindings) {
			if(b.listenerOut!=nil) removelistener(b.listenerOut);
			b.listenerOut = setlistener(b.control, 
				(func func {
					if(getprop(getprop("/copilot/host-MP-path")~b.trans) != getprop(b.control)) { #match means I received the control change - do not transmit
						#mismatch means I triggered the control change
						var tr = getprop(b.control);
						if(tr!=nil) {
							#hack-around for ignored update when value does not change
							if(props.globals.getNode(b.trans).getType()!="STRING" and tr==getprop(b.trans)) tr = tr<0 ? tr-0.00001 : tr+0.00001;
							setprop(b.trans, tr);
						}
						b.timer.start(); #timer ensures I don't receive control changes when I'm doing changes myself
					}
				})(b:b)
			, 0 , 0);
			
		}
	},
	
	#not sure if needed at all, transmit can run all the time
	stopTransmitControlsGuest: func {
		foreach(var b; me.bindings) {
			if(b.listenerOut!=nil) removelistener(b.listenerOut);
			b.listenerOut = nil;
		}
	},
	
	receiveControlsGuest: func(iMP) {
		foreach(var b; me.bindings) {
			if(b.listenerIn!=nil) removelistener(b.listenerIn);
			b.listenerIn = setlistener("/ai/models/multiplayer["~iMP~"]"~b.trans, 
				(func func {
					if(!b.timer.isRunning) {
						var cont = getprop("/ai/models/multiplayer["~iMP~"]"~b.trans);
						if(cont!=nil) setprop(b.control, cont);
					}
				})(b:b, iMP:iMP)
			, 0 , 0);
		}
		#initial sync
		foreach(var b; me.bindings) {
			var cont = getprop("/ai/models/multiplayer["~iMP~"]"~b.trans);
			if(cont!=nil) setprop(b.control, cont);
		}
	},
	
	forceReceiveControlsGuest: func {
		var sourceMpString = getprop("/copilot/host-MP-path");
		if(sourceMpString==nil or sourceMpString=="") return;
		foreach(var b; me.bindings) {
			if(!b.timer.isRunning) {
				var cont = getprop(sourceMpString~b.trans);
				if(cont!=nil) setprop(b.control, cont);
			}
		}
	},
	
	stopReceiveControlsGuest: func {
		foreach(var b; me.bindings) {
			if(b.listenerIn!=nil) removelistener(b.listenerIn);
			b.listenerIn = nil;
		}
	},
	
	#############################
	### Host handling methods ###
	#############################
	
	#check for new MP aircraft and set listener on their model id path
	handleNewMP: func {
		var mpList = props.globals.getNode("/ai/models").getChildren("multiplayer");
		forindex(var iMP; mpList) {
			if(me.knownMP>=iMP) continue;
			
			#print(me.name~": Handling new MP "~iMP); #DEBUG
			
			setlistener(mpList[iMP].getPath()~"/sim/model/path", (func func{me.handleIdChange(iMP);})(iMP:iMP), 1, 0);
			
			me.knownMP = iMP;
		}
	},
	
	#when an MP aircraft changes aircraft type or when first appears, check for matching model id and set/remove listener on handshakeString
	handleIdChange: func(iMP) {
		#print(me.name~": Handling ID change for MP "~iMP); #DEBUG
		if(size(me.listenMpHandshakes)<=iMP) setsize(me.listenMpHandshakes, iMP+1);
		var mpId = getprop("/ai/models/multiplayer["~iMP~"]/sim/model/path");
		if(mpId!=nil and streq(mpId, me.id)) {
			if(me.listenMpHandshakes[iMP]==nil) {
				me.listenMpHandshakes[iMP] = setlistener("/ai/models/multiplayer["~iMP~"]"~handshakeString, func{me.checkForRequest(arg[0]);}, 1, 0);
				#print(me.name~": Adding listener on handshake string..."); #DEBUG
			}
		}
		else {
			if(me.listenMpHandshakes[iMP]!=nil) {
				removelistener(me.listenMpHandshakes[iMP]);
				me.listenMpHandshakes[iMP] = nil;
			}
		}
	},
	
	#check for request broadcast via handshakeString
	checkForRequest: func(strNode) {
		var str = strNode.getValue();
		if(str==nil) return;
		var spl = split(":", str);
		var baseMpNode = strNode.getParent().getParent().getParent().getParent();
		if(size(spl)==2 and streq(spl[0], me.name) and streq(spl[1], getprop("/sim/multiplay/callsign")) and baseMpNode.getChild("valid").getValue()) {
			DualControls_GUI.addRequest(
				Request.new(
					baseMpNode.getChild("callsign").getValue(), 
					me.name, 
					strNode.getPath(), 
					me.confirmR, 
					baseMpNode.getIndex(),
					me
				)
			);
		}
	},
	
	#confirm request wrapper to fix problem with me. reference
	confirmR: func(request) {
		request.meRef.confirmReq(request);
	},
	
	#confirm request
	confirmReq: func(request) {
		if(!request.valid) {
			if(request.callsign!=nil) screen.log.write(request.callsign~" already canceled the request for position "~me.name);
			return;
		}
		
		
		setprop("/copilot/onboard/"~request.position, request.callsign);
		
		if(me.onBoardListeners.mp!=nil) removelistener(me.onBoardListeners.mp);
		if(me.onBoardListeners.valid!=nil) removelistener(me.onBoardListeners.valid);
		if(me.onBoardListeners.local!=nil) removelistener(me.onBoardListeners.local);
		if(me.onBoardListeners.frame!=nil) removelistener(me.onBoardListeners.frame);
		me.stopReceiveControlsHost();
		
		var iMP = request.mpIndex;
		
		me.onBoardListeners.mp = setlistener(request.listenValidPath, 
			func {
				me.left();
			}
		, 0, 0);
		me.onBoardListeners.valid = setlistener("/ai/models/multiplayer["~request.mpIndex~"]/valid", 
			func {
				if(!arg[0].getValue()) me.left();
			}
		, 1, 0);
		me.onBoardListeners.local = setlistener("/copilot/onboard/"~me.name, 
			(func func {
				me.kick(kickCall);
			})(kickCall:getprop("/copilot/onboard/"~me.name))
		, 0, 0);

		me.receiveControlsHost(iMP);
		me.transmitControlsHost();
		
		var callsign = getprop("/copilot/onboard/"~me.name);
		if(callsign!=nil) screen.log.write("You have accepted "~callsign~" on position "~me.name);
		
	},
	
	#function handling case when guest left or got offline
	left: func {
		if(me.onBoardListeners.mp!=nil) {
			removelistener(me.onBoardListeners.mp);
			me.onBoardListeners.mp = nil;
		}
		if(me.onBoardListeners.valid!=nil) {
			removelistener(me.onBoardListeners.valid);
			me.onBoardListeners.valid = nil;
		}
		if(me.onBoardListeners.local!=nil) {
			removelistener(me.onBoardListeners.local);
			me.onBoardListeners.local = nil;
		}
		if(me.onBoardListeners.frame!=nil) {
			removelistener(me.onBoardListeners.frame);
			me.onBoardListeners.frame = nil;
		}
		me.stopReceiveControlsHost();
		var callsign = getprop("/copilot/onboard/"~me.name);
		setprop("/copilot/onboard/"~me.name, "");
		if(callsign!=nil) screen.log.write(callsign~" have left from position "~me.name);
	},
	
	#function handling case when I kick out/change guest
	kick: func(kickCall) {
		if(me.onBoardListeners.mp!=nil) {
			removelistener(me.onBoardListeners.mp);
			me.onBoardListeners.mp = nil;
		}
		if(me.onBoardListeners.valid!=nil) {
			removelistener(me.onBoardListeners.valid);
			me.onBoardListeners.valid = nil;
		}
		if(me.onBoardListeners.local!=nil) {
			removelistener(me.onBoardListeners.local);
			me.onBoardListeners.local = nil;
		}
		if(me.onBoardListeners.frame!=nil) {
			removelistener(me.onBoardListeners.frame);
			me.onBoardListeners.frame = nil;
		}
		me.stopReceiveControlsHost();
		if(kickCall!=nil) screen.log.write("You removed "~kickCall~" from position "~me.name);
	},
	
	receiveControlsHost: func(iMP) {
		foreach(var b; me.bindings) {
			if(b.listenerIn!=nil) removelistener(b.listenerIn);
			b.listenerIn = setlistener("/ai/models/multiplayer["~iMP~"]"~b.trans, 
				(func func {
					if(getprop("/copilot/accept-controls/"~me.name)) {
						var tr = arg[0].getValue();
						if(tr!=nil) {
							#fix hack-around for bool values
							if(arg[0].getType()!="STRING" and tr>0 and tr<0.000011) tr = 0;
							setprop(b.control, tr);
						}
					}
				})(b:b)
			, 0 , 0);
			
		}
	},
	
	stopReceiveControlsHost: func {
		foreach(var b; me.bindings) {
			if(b.listenerIn!=nil) removelistener(b.listenerIn);
			b.listenerIn = nil;
		}
	},
	
	#transmits controls by copying them to specified transfer properties
	transmitControlsHost: func() {
		foreach(var b; me.bindings) {
			if(b.listenerOut==nil) {
				b.listenerOut = setlistener(b.control, 
					(func func {
							var tr = getprop(b.control);
							if(tr!=nil and getprop("/copilot/two-way-sync")) setprop(b.trans, tr);
					})(b:b)
				, 1 , 0);
			}
		}
	},
};

#############################################
### Property transfer binding definitions ###
#############################################
#
# It is highly remommended to use double properties even for int/bool values to prevent certain issues with ignored input
#
# /engines/engine[#]/n1, n2, rpm provide many MP transferred properties. If you have less than 9 engines (you do!),
# use those that are not needed, or standard /sim/multiplay/generic/float[#]


var instructor = Position.new("Instructor", "Aircraft/L-159/Models/L-159-instructor.xml");
instructor.controlBind("/controls/flight/elevator", "/engines/engine[1]/n1", "DOUBLE");
instructor.controlBind("/controls/flight/aileron", "/engines/engine[1]/n2", "DOUBLE");
instructor.controlBind("/controls/flight/rudder", "/engines/engine[1]/rpm", "DOUBLE");
instructor.controlBind("/controls/flight/elevator-trim", "/engines/engine[2]/n1", "DOUBLE");
instructor.controlBind("/controls/flight/aileron-trim", "/engines/engine[2]/n2", "DOUBLE");
instructor.controlBind("/controls/flight/rudder-trim", "/engines/engine[2]/rpm", "DOUBLE");
instructor.controlBind("/sim/flaps/current-setting", "/engines/engine[3]/n1", "DOUBLE");
instructor.controlBind("/controls/flight/speedbrake", "/engines/engine[3]/n2", "DOUBLE");
instructor.controlBind("/controls/engines/engine/throttle", "/engines/engine[3]/rpm", "DOUBLE");
instructor.controlBind("/controls/gear/brake-left", "/engines/engine[4]/n1", "DOUBLE");
instructor.controlBind("/controls/gear/brake-right", "/engines/engine[4]/n2", "DOUBLE");
instructor.controlBind("/controls/gear/brake-parking", "/engines/engine[4]/rpm", "DOUBLE");
instructor.controlBind("/controls/gear/gear-down", "/engines/engine[7]/rpm", "DOUBLE");
#autopilot sync
instructor.controlBind("/autopilot/locks/heading", "/sim/multiplay/generic/string[2]", "STRING");
instructor.controlBind("/autopilot/locks/speed", "/sim/multiplay/generic/string[3]", "STRING");
instructor.controlBind("/autopilot/locks/altitude", "/sim/multiplay/generic/string[4]", "STRING");
instructor.controlBind("/autopilot/settings/heading-bug-deg", "/engines/engine[5]/n1", "DOUBLE");
instructor.controlBind("/autopilot/settings/true-heading-deg", "/engines/engine[5]/n2", "DOUBLE");
instructor.controlBind("/autopilot/settings/target-speed-kt", "/engines/engine[5]/rpm", "DOUBLE");
instructor.controlBind("/autopilot/settings/vertical-speed-fpm", "/engines/engine[6]/n1", "DOUBLE");
instructor.controlBind("/autopilot/settings/target-pitch-deg", "/engines/engine[6]/n2", "DOUBLE");
instructor.controlBind("/autopilot/settings/target-aoa-deg", "/engines/engine[6]/rpm", "DOUBLE");
instructor.controlBind("/autopilot/settings/target-altitude-ft", "/engines/engine[7]/n1", "DOUBLE");
instructor.controlBind("/autopilot/settings/target-agl-ft", "/engines/engine[7]/n2", "DOUBLE");


var wingsitter = Position.new("Wingsitter", "Aircraft/L-159/Models/L-159-wingsitter.xml");
wingsitter.controlBind("/controls/flight/aileron", "/engines/engine[1]/n1", "DOUBLE");




print("L-159 dual controls sync code initialized");

