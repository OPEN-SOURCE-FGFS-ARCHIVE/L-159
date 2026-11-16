#node holding the current MP 
props.globals.initNode("/copilot/host-MP-path", "", "STRING");

#model path to match
var hostModel = "Aircraft/L-159/Models/L-159.xml";


### Dialog creating requests ###
var PICKHOST_DLG = 0;
var pickHost_dialog = {};
pickHost_dialog.x = nil;
pickHost_dialog.y = nil;
############################################################
pickHost_dialog.init = func (host_type, title, x = nil, y = nil) {
	if(x!=nil) me.x = x;
	if(x!=nil) me.y = y;
	me.bg = [0, 0, 0, 0.3]; # background color
	me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
	#
	# "private"
	me.title = title;
	
	me.basenode = props.globals.getNode("/sim/remote", 1);
	me.dialog = nil;
	me.namenode = props.Node.new({"dialog-name" : me.title });
	me.host_type = host_type;
	props.globals.initNode(me.basenode.getPath()~"/host-callsign", "", "STRING");
}
############################################################
pickHost_dialog.create = func {
	if (me.dialog != nil)
		me.close();

	me.dialog = gui.Widget.new();
	me.dialog.set("name", me.title);
	if (me.x != nil)
		me.dialog.set("x", me.x);
	if (me.y != nil)
		me.dialog.set("y", me.y);

	me.dialog.set("layout", "vbox");
	me.dialog.set("default-padding", 0);
	var titlebar = me.dialog.addChild("group");
	titlebar.set("layout", "hbox");
	titlebar.addChild("empty").set("stretch", 1);
	titlebar.addChild("text").set("label", "Hosts available online");
	var w = titlebar.addChild("button");
	w.set("pref-width", 16);
	w.set("pref-height", 16);
	w.set("legend", "");
	w.set("default", 0);
	w.set("key", "esc");
	w.setBinding("nasal", "DualControls_GUI.pickHost_dialog.destroy(); ");
	w.setBinding("dialog-close");
	me.dialog.addChild("hrule");

	var content = me.dialog.addChild("group");
	content.set("layout", "vbox");
	content.set("halign", "center");
	content.set("default-padding", 5);

	# Generate the dialog contents.
	me.players = me.find_copilot_players();
	var i = 0;
	var tmpbase  = me.basenode.getNode("dialog", 1);
	var selected = me.basenode.getNode("host-callsign").getValue();
	foreach (var p; me.players) {
		var tmp = tmpbase.getNode("b[" ~ i ~ "]", 1);
		tmp.setBoolValue(streq(selected, p));
		var w = content.addChild("checkbox");
		w.node.setValues({"label"	: p,
						  "halign"   : "left",
						  "property" : tmp.getPath()});
		w.setBinding
			("nasal",
			 "DualControls_GUI.pickHost_dialog.select_action(" ~ i ~ ");");
		i = i + 1;
	}	
	
	me.dialog.addChild("hrule");
	
	var b = content.addChild("button");
	b.set("legend", "Leave host");
	b.set("default", 1);
	b.set("key", "Enter");
	b.setBinding("nasal", "
		setprop(DualControls_GUI.pickHost_dialog.basenode.getNode(\"host-callsign\").getPath(), \"\"); 
		DualControls_GUI.pickHost_dialog.leave(); 
		DualControls_GUI.pickHost_dialog.destroy();"
	);

	# Display the dialog.
	fgcommand("dialog-new", me.dialog.prop());
	fgcommand("dialog-show", me.namenode);
}
############################################################
pickHost_dialog.close = func {
	var xNode = me.dialog.prop().getNode("x");
	var yNode = me.dialog.prop().getNode("y");
	if(xNode!=nil) me.x = xNode.getValue();
	if(yNode!=nil) me.y = yNode.getValue();
	fgcommand("dialog-close", me.namenode);
}
############################################################
pickHost_dialog.destroy = func {
	PICKHOST_DLG = 0;
	me.close();
	delete(gui.dialog, "\"" ~ me.title ~ "\"");
}
############################################################
pickHost_dialog.show = func (host_type, title) {
	if (!PICKHOST_DLG) {
		# +1 prevents problems in case of bringing up the dialog too early on startup, when time is 0
		PICKHOST_DLG = int(getprop("/sim/time/elapsed-sec") + 1);
		me.init(host_type, title);
		me.create();
		me._update_(PICKHOST_DLG);
	}
}
############################################################
pickHost_dialog._redraw_ = func {
	if (me.dialog != nil) {
		me.close();
		me.create();
	}
}
############################################################
pickHost_dialog._update_ = func (id) {
	if (PICKHOST_DLG != id) return;
	me._redraw_();
	settimer(func { me._update_(id); }, 4.1);
}
############################################################
pickHost_dialog.select_action = func (n) {
	var selected = me.basenode.getNode("host-callsign").getValue();
	var bs = me.basenode.getNode("dialog").getChildren();
	# Assumption: There are two true b:s or none. The one not matching selected
	#			 is the new selection.
	var i = 0;
	me.basenode.getNode("host-callsign").setValue("");
	foreach (var b; bs) {
		if (!b.getValue() and (i == n)) {
			b.setValue(1);
			me.basenode.getNode("host-callsign").setValue(me.players[i]);
		} else {
			b.setValue(0);
		}
		i = i + 1;
	}
	
	var isRequest = 0;
	
	foreach(var nodeMP; props.globals.getNode("/ai/models").getChildren("multiplayer")) {
		var thisCall = nodeMP.getNode("callsign").getValue();
		if( thisCall!=nil and streq(thisCall, me.basenode.getNode("host-callsign").getValue()) ) {
			setprop("/copilot/host-MP-path-request", nodeMP.getPath());
			isRequest = 1;
		}
	}
	
	if(!isRequest) me.leave();
	
	#dual_control.main.reset();
	me._redraw_();
}
############################################################
pickHost_dialog.leave = func() {
	setprop("/copilot/host-MP-path-request", "");
	setprop(DualControls.handshakeString, "");
	setprop("/copilot/host-MP-path", "");
}
############################################################
# Return a list containing all nearby copilot players of the right type.
pickHost_dialog.find_copilot_players = func {
	var mpplayers =
		props.globals.getNode("/ai/models").getChildren("multiplayer");

	var res = [];
	foreach (var pilot; mpplayers) {
		if ((pilot.getNode("valid") != nil) and
			(pilot.getNode("valid").getValue()) and
			(pilot.getNode("sim/model/path") != nil)) {
			var type = pilot.getNode("sim/model/path").getValue();

			if (type == me.host_type) {
				append(res, pilot.getNode("callsign").getValue());
			}
		}
	}
#	debug.dump(res);
	return res; 
}






### Dialog handling requests ###
var CONFHOST_DLG = 0;
var confirmHost_dialog = {};
confirmHost_dialog.x = 20;
confirmHost_dialog.y = 20;
############################################################
confirmHost_dialog.init = func (reqObj, x = nil, y = nil) {
	if(x!=nil) me.x = x;
	if(x!=nil) me.y = y;
	me.bg = [0, 0, 0, 0.3]; # background color
	me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
	#
	# "private"
	me.title = "Request from "~reqObj.callsign~" for position "~reqObj.position;
	me.reqObj = reqObj;
	me.callbackConfirm = reqObj.callbackConfirm;
	
	me.dialog = nil;
	me.namenode = props.Node.new({"dialog-name" : me.title });
}
############################################################
confirmHost_dialog.create = func {
	if (me.dialog != nil)
		me.close();

	me.dialog = gui.Widget.new();
	me.dialog.set("name", me.title);
	if (me.x != nil)
		me.dialog.set("x", me.x);
	if (me.y != nil)
		me.dialog.set("y", me.y);

	me.dialog.set("layout", "vbox");
	me.dialog.set("default-padding", 0);
	var titlebar = me.dialog.addChild("group");
	titlebar.set("layout", "hbox");
	titlebar.addChild("empty").set("stretch", 1);
	titlebar.addChild("text").set("label", me.title);
	me.dialog.addChild("hrule");

	var content = me.dialog.addChild("group");
	content.set("layout", "vbox");
	content.set("halign", "center");
	content.set("default-padding", 5);

	
	
	var occ = getprop("/copilot/onboard/"~me.reqObj.position);
	var occText = "";
	if(occ==nil or occ=="") occText = "Position is empty";
	else occText = "Position occupied by "~occ;
	
	content.addChild("text").set("label", occText);
	
	
	
	var bConfirm = content.addChild("button");
	bConfirm.set("legend", "Confirm");
	bConfirm.set("default", 0);
	bConfirm.setBinding("nasal", "
		DualControls_GUI.confirmHost_dialog.callbackConfirm(DualControls_GUI.confirmHost_dialog.reqObj);
		DualControls_GUI.confirmHost_dialog.destroy();"
	);
	
	var bIgnore = content.addChild("button");
	bIgnore.set("legend", "Ignore");
	bIgnore.set("default", 0);
	bIgnore.setBinding("nasal", "DualControls_GUI.confirmHost_dialog.destroy();");
	
	me.dialog.addChild("hrule");
	
	screen.log.write(me.reqObj.callsign~" requests position "~me.reqObj.position);

	# Display the dialog.
	fgcommand("dialog-new", me.dialog.prop());
	fgcommand("dialog-show", me.namenode);
}
############################################################
confirmHost_dialog.close = func {
	var xNode = me.dialog.prop().getNode("x");
	var yNode = me.dialog.prop().getNode("y");
	if(xNode!=nil) me.x = xNode.getValue();
	if(yNode!=nil) me.y = yNode.getValue();
	fgcommand("dialog-close", me.namenode);
}
############################################################
confirmHost_dialog.destroy = func {
	CONFHOST_DLG = 0;
	me.close();
	delete(gui.dialog, "\"" ~ me.title ~ "\"");
	me.reqObj.delListener();
	processRequests();
}
############################################################
confirmHost_dialog.show = func (reqObj) {
	if (!CONFHOST_DLG) {
		# +1 prevents problems in case of bringing up the dialog too early on startup, when time is 0
		CONFHOST_DLG = int(getprop("/sim/time/elapsed-sec") + 1);
		me.init(reqObj);
		me.create();
	}
}




#request queue handling
var requests = [];
var addRequest = func(reqObj) {
	append(requests, reqObj);
	processRequests();
}

var processRequests = func {
	#flush all requests if ignore is on
	if(getprop("/copilot/ignore-requests")) requests = [];
	#do nothing if request is being processed (there is dialog opened) or there are no more requests
	if(CONFHOST_DLG or size(requests)<1) return();
	#extract oldest request
	var req = requests[0];
	requests = subvec(requests, 1);
	#open confirm dialog with the request
	if(req.valid) confirmHost_dialog.show(req);
	else {
		settimer(processRequests, 0);
		req.delListener();
	}
}




#dialog handling controls receiving on/off and removing guests
var MANAGEGUESTS_DLG = 0;
var manageGuests_dialog = {};
manageGuests_dialog.x = nil;
manageGuests_dialog.y = nil;
############################################################
manageGuests_dialog.init = func (x = nil, y = nil) {
	if(x!=nil) me.x = x;
	if(x!=nil) me.y = y;
	me.bg = [0, 0, 0, 0.3]; # background color
	me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
	#
	# "private"
	me.title = "Multiplayer dual controls guests management";
	
	me.dialog = nil;
	me.namenode = props.Node.new({"dialog-name" : me.title });
}
############################################################
manageGuests_dialog.create = func {
	if (me.dialog != nil)
		me.close();

	me.dialog = gui.Widget.new();
	me.dialog.set("name", me.title);
	if (me.x != nil)
		me.dialog.set("x", me.x);
	if (me.y != nil)
		me.dialog.set("y", me.y);

	me.dialog.set("layout", "vbox");
	me.dialog.set("default-padding", 0);
	var titlebar = me.dialog.addChild("group");
	titlebar.set("layout", "hbox");
	titlebar.addChild("empty").set("stretch", 1);
	titlebar.addChild("text").set("label", me.title);
	var w = titlebar.addChild("button");
	w.set("pref-width", 16);
	w.set("pref-height", 16);
	w.set("legend", "");
	w.set("default", 0);
	w.set("key", "esc");
	w.setBinding("nasal", "DualControls_GUI.manageGuests_dialog.destroy(); ");
	w.setBinding("dialog-close");
	me.dialog.addChild("hrule");
	
	var checks = me.dialog.addChild("group");
	checks.set("layout", "hbox");
	#checks.addChild("empty").set("stretch", 1);
	
	var ignoreRequests = checks.addChild("checkbox");
	ignoreRequests.set("property", "/copilot/ignore-requests");
	ignoreRequests.set("label", "Ignore all requests");
	ignoreRequests.setBinding("dialog-apply");
	#ignoreRequests.set("pref-height", 25);
	
	var twoWaySync = checks.addChild("checkbox");
	twoWaySync.set("property", "/copilot/two-way-sync");
	twoWaySync.set("label", "Enable two-way sync");
	twoWaySync.setBinding("dialog-apply");
	#twoWaySync.set("pref-height", 25);
	
	me.dialog.addChild("hrule");

	var content = me.dialog.addChild("group");
	content.set("layout", "table");
	#content.set("default-padding", 5);
	
	#helper for adding element to specified table cell
	var tcell = func(parent, type, row, col) {
		var cell = parent.addChild(type);
		cell.set("row", row);
		cell.set("col", col);
		return cell;
	}
	
	tcell(content, "text", 0, 0).set("label", "Position");
	tcell(content, "text", 0, 1).set("label", "Accept controls");
	tcell(content, "text", 0, 2).set("label", "Occupied by");
	
	
	var guests = props.globals.getNode("/copilot/onboard").getChildren();
	
	forindex(var iGuest; guests) {
		var posName = guests[iGuest].getName();
		var occupiedBy = guests[iGuest].getValue();
		
		tcell(content, "text", iGuest+1, 0).set("label", posName);
		
		var acceptContCheck = tcell(content, "checkbox", iGuest+1, 1);
		acceptContCheck.set("property", "/copilot/accept-controls/"~posName);
		acceptContCheck.setBinding("dialog-apply");
		
		tcell(content, "text", iGuest+1, 2).set("label", occupiedBy==nil?"":occupiedBy);
		
		if(occupiedBy!=nil and occupiedBy!="") {
			var removeButton = tcell(content, "button", iGuest+1, 3);
			removeButton.set("legend", "Kick out");
			removeButton.set("default", 0);
			removeButton.setBinding("nasal",
				"setprop(\"/copilot/onboard/"~posName~"\", \"\");");
			removeButton.setBinding("nasal",
				"DualControls_GUI.manageGuests_dialog._redraw_();");
		}
	}
	
	me.dialog.addChild("hrule");
	
	# Display the dialog.
	fgcommand("dialog-new", me.dialog.prop());
	fgcommand("dialog-show", me.namenode);
}
############################################################
manageGuests_dialog.close = func {
	var xNode = me.dialog.prop().getNode("x");
	var yNode = me.dialog.prop().getNode("y");
	if(xNode!=nil) me.x = xNode.getValue();
	if(yNode!=nil) me.y = yNode.getValue();
	fgcommand("dialog-close", me.namenode);
}
############################################################
manageGuests_dialog.destroy = func {
	MANAGEGUESTS_DLG = 0;
	me.close();
	delete(gui.dialog, "\"" ~ me.title ~ "\"");
}
############################################################
manageGuests_dialog.show = func () {
	if (!MANAGEGUESTS_DLG) {
		# +1 prevents problems in case of bringing up the dialog too early on startup, when time is 0
		MANAGEGUESTS_DLG = int(getprop("/sim/time/elapsed-sec") + 1);
		me.init();

		me.create();
		me._update_(MANAGEGUESTS_DLG);
	}
}
############################################################
manageGuests_dialog._redraw_ = func {
	if (me.dialog != nil) {
		me.close();
		me.create();
	}
}
############################################################
manageGuests_dialog._update_ = func (id) {
	if (MANAGEGUESTS_DLG != id) return;
	me._redraw_();
	settimer(func { me._update_(id); }, 4.1);
}




print("L-159 dual controls GUI code initialized");


