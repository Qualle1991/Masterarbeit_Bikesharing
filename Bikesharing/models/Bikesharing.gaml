/*
* Name: Bikesharing
* Author: Pascal Schwerk
* Description: Game on Luckenwalde with bikesharing, based on Game It by Tallaindier et al. and Eberswalde by //TODO
* Tags: bikesharing, newmobility
*/
model Bikesharing

global {

	//ENVIRONMENT
	float step <- 10 #mn update: 10 #mn;
	date starting_date <- date([2020, 4, 1, 0, 0]);
	// case_study needs a folder named like the city in focus
	string case_study <- "luckenwalde";
	string EPSG <- "EPSG:25833";
	//URL for Google Forms result:
	string url <- "https://docs.google.com/spreadsheets/d/e/2PACX-1vRdj4Dvf3TyVUgbW2jF3YN7NXbrN1qUGa3XGhiiiMiARxpMXsKRyzugMY3eglHjsRLLtZPiOhbOEG1e/pub?gid=2013234065&single=true&output=csv";
	
	//USER INTERACTION:	
	//Choice for using Google forms instead of fixed profile_file:
	string profile_input_mode <- "Feste Profil-Datei" among: ["Feste Profil-Datei", "Google Umfrage"] parameter: "Profil Import" category: "Voreinstellung";
	int nb_people <- 500 parameter: "Anzahl der Personen: " min: 1 max: 10000 category: "Voreinstellung";
	int nb_pendler <- 25 parameter: "Anzahl der Pendler: " min: 5 max: 1000category: "Voreinstellung";
	int nb_shared_bikes <- 200 parameter: "Anzahl der Shared Bikes: " min: 0 max: 1000category: "Voreinstellung";
	//Choice for sharing_station-creation-mode:
	string creation_mode <- "Off" among: ["On", "Off"] parameter: "Klickaktion" category: "Interaktion";
	
	//Shapefiles:
	string ProjectFolder <- "./../includes/City/" + case_study;
	file<geometry> buildings_shapefile <- shape_file(ProjectFolder + "/buildings.shp");
	file<geometry> external_shapefile <- shape_file(ProjectFolder + "/external_cities.shp");
	file<geometry> roads_shapefile <- shape_file(ProjectFolder + "/roads.shp");
	//file<geometry> roads_shapefile <- shape_file(ProjectFolder + "/200219 Luckenwalde highways 1437.shp");
	file<geometry> bus_shapefile <- shape_file(ProjectFolder + "/bus_stops.shp");
	file<geometry> bikesharing_shapefile <- shape_file(ProjectFolder + "/sharing_stations.shp");
	//file background_img <- file(GISFolder + "/background.jpg");
	geometry shape <- envelope(roads_shapefile);

	//ROAD SPEED LIMIT
	float max_speed_general <- 50.0;

	//User Interaction in Charts abbilden
	int gui_action <- 0;

	// MOBILITY DATA
	list<string> mobility_list <- ["walking", "bike", "car", "bus", "shared_bike"];
	file activity_file <- file(ProjectFolder + "profiles_and_modes/ActivityPerProfile.csv");
	file criteria_file <- file(ProjectFolder + "profiles_and_modes/CriteriaFile.csv");
	file mode_file <- file(ProjectFolder + "profiles_and_modes/Modes.csv");
	file profile_file;

	//MAPS
	map<string, rgb> color_per_category <- ["Restaurant"::#green, "Night"::#dimgray, "GP"::#dimgray, "Cultural"::#green, "Park"::#green, "Shopping"::#green, "HS"::#darkorange, "Uni"::#pink, "O"::#gray, "R"::#grey];
	map<string, rgb> color_per_type <- ["Studierende"::#purple, "Schueler"::#gamablue, "Arbeitnehmer"::#cornflowerblue, "Fuehrungskraefte"::#lightgrey, "Heimzentrierte"::#yellow, "Rentner"::#mediumturquoise];
	map<string, map<string, int>> activity_data;
	map<string, float> proportion_per_type;
	map<string, float> proba_bike_per_type;
	map<string, float> proba_car_per_type;
	map<string, float> proba_bikesharing_per_type;
	map<string, rgb> color_per_mobility;
	map<string, float> width_per_mobility;
	map<string, float> speed_per_mobility;
	map<string, graph> graph_per_mobility;
	map<string, list<float>> charact_per_mobility;
	map<road, float> congestion_map;
	map<string, map<string, list<float>>> weights_map <- map([]);

	// INDICATOR
	map<string, int> transport_type_cumulative_usage <- map(mobility_list collect (each::0));
	map<string, int> transport_type_cumulative_usage_per_day <- map(mobility_list collect (each::0));
	map<string, int> buildings_distribution <- map(color_per_category.keys collect (each::0));

	//TESTING-COUNTERS
	int counter_rides <- 0;
	int counter_succeeded <- 0;
	int count_missed_bike <- 0;
	
	init {
		//gama.pref_display_flat_charts <- true;
		
		create road from: roads_shapefile //TODO with: [mobility_allowed::(string(read("mobility_a")) split_with "|")] 
		{
			mobility_allowed <- ["walking", "bike", "car", "bus", "shared_bike"];
			capacity <- shape.perimeter / 10.0;
			congestion_map[self] <- 10.0; //shape.perimeter;
		}

		// Buildings including heigt from building level if in data, else random building level between 1 and 5:
		create building from: buildings_shapefile with: [usage::string(read("usage")), scale::string(read("scale")), category::string(read("category")), level::int(read("building_l"))] {
			color <- color_per_category[category];
			if (level > 0) {
				height <- 2.6 * level;
			} else {
				if (category in ["Park", "Cultural"]) {
					height <- 0.0;
				} else {
					height <- 2.6 * rnd(1, 5);
				}

			}

		}

		create externalCities from: external_shapefile with: [train::bool(get("train"))];
		create bus_stop from: bus_shapefile;
		create sharing_station from: bikesharing_shapefile;

		// Bus EBW
		create bus {
			stops <- list(bus_stop);
			location <- first(stops).location;
			stop_passengers <- map<bus_stop, list<people>>(stops collect (each::[]));
		}

/*
		// Four Busses for Luckenwalde to simulate an hourly cycle:
		loop i from: 0 to: 3 {
			create bus {
				stops <- list(bus_stop);
				location <- stops[i * 8].location;
				loop y from: 0 to: i * 8 {
					bus_stop firstStop <- first(stops);
					remove firstStop from: stops;
					add firstStop to: stops;
				}

				stop_passengers <- map<bus_stop, list<people>>(stops collect (each::[]));
			}

		}
		* 
		*/
		
		// shared_bikes are distributed randomly at the sharing_stations:
		create shared_bike number: nb_shared_bikes {
			location <- one_of(sharing_station).location;
			in_use <- false;
			closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
			color <- #red;
			add self to: closest_sharing_station.parked_bikes;
		}

		// imports for people data:
		do import_profile_file;
		do profils_data_import;
		do activity_data_import;
		do criteria_file_import;
		do characteristic_file_import;
		// mobility_graph:
		do compute_graph;
		
		create people number: nb_people {
		//   		 type <- proportion_per_type.keys[rnd_choice(proportion_per_type.values)];
		//   		 has_car <- flip(proba_car_per_type[type]);
		//   		 has_bike <- flip(proba_bike_per_type[type]);
		//   		 living_place <- one_of(building where (each.usage = "R"));
		//   		 current_place <- living_place;
		//   		 location <- any_location_in(living_place);
		//   		 color <- color_per_type[type];
		//   		 closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
		//   		 do create_trip_objectives;
			type <- proportion_per_type.keys[rnd_choice(proportion_per_type.values)];
			has_car <- true;
			has_bike <- true;
			living_place <- one_of(building where (each.usage = "R"));
			current_place <- living_place;
			location <- any_location_in(living_place);
			color <- color_per_type[type];
			closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
			do create_trip_objectives;
		}

		//nb_pendler
		ask externalCities {
			create people number: int(nb_pendler / 5) {
				type <- proportion_per_type.keys[rnd_choice(proportion_per_type.values)];
				if myself.train = false {
					has_car <- true;
					has_bike <- flip(proba_bike_per_type[type]);
				} else {
					has_car <- false;
					has_bike <- flip(proba_bike_per_type[type]);
				}

				living_place <- myself;
				current_place <- living_place;
				location <- any_location_in(living_place);
				color <- color_per_type[type];
				closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
				do create_trip_objectives;
			}

		}

		create map_interaction_button number: 1 with: [button_name::"Alle Strassen für Autos sperren", type:: 1, location::{0, world.shape.height * 0.8}];
		//create map_interaction_button number: 1 with: [button_name::"Alle Strassen für Autos freigeben", type:: 2, location::{ 0, world.shape.height * 0.8 }];
	}

	action choose_map_interaction {
		ask map_interaction_button overlapping (rectangle(1100, 100) at_location #user_location) {
			ask map_interaction_button {
				active <- false;
			}

			active <- true;
			if (self.type = 1) {
				do all_roads_to_pedestrian;
			} else {
				do all_roads_to_normal;
			}

		}

	}

	action profils_data_import {
		matrix profile_matrix <- matrix(profile_file);
		loop i from: 0 to: profile_matrix.rows - 1 {
			string profil_type <- profile_matrix[0, i];
			if (profil_type != "") {
				proba_car_per_type[profil_type] <- float(profile_matrix[2, i]);
				proba_bike_per_type[profil_type] <- float(profile_matrix[3, i]);
				proportion_per_type[profil_type] <- float(profile_matrix[4, i]);
			}

		}

	}

	action activity_data_import {
		matrix activity_matrix <- matrix(activity_file);
		loop i from: 1 to: activity_matrix.rows - 1 {
			string people_type <- activity_matrix[0, i];
			map<string, int> activities;
			string current_activity <- "";
			loop j from: 1 to: activity_matrix.columns - 1 {
				string act <- activity_matrix[j, i];
				if (act != current_activity) {
					activities[act] <- j;
					current_activity <- act;
				}

			}

			activity_data[people_type] <- activities;
		}

	}

	action click_to_pedestrian_road {
		ask road closest_to #user_location {
			do to_pedestrian_road_ext;
		}

	}

	action criteria_file_import {
		matrix criteria_matrix <- matrix(criteria_file);
		int nbCriteria <- criteria_matrix[1, 0] as int;
		int nbTO <- criteria_matrix[1, 1] as int;
		int lignCategory <- 2;
		int lignCriteria <- 3;
		loop i from: 5 to: criteria_matrix.rows - 1 {
			string people_type <- criteria_matrix[0, i];
			int index <- 1;
			map<string, list<float>> m_temp <- map([]);
			if (people_type != "") {
				list<float> l <- [];
				loop times: nbTO {
					list<float> l2 <- [];
					loop times: nbCriteria {
						add float(criteria_matrix[index, i]) to: l2;
						index <- index + 1;
					}

					string cat_name <- criteria_matrix[index - nbTO, lignCategory];
					loop cat over: cat_name split_with "|" {
						add l2 at: cat to: m_temp;
					}

				}

				add m_temp at: people_type to: weights_map;
			}

		}

	}

	action characteristic_file_import {
		if (szenario = "City-Maut") {
			matrix mode_matrix <- matrix(mode_file);
			loop i from: 0 to: mode_matrix.rows - 1 {
				string mobility_type <- mode_matrix[0, i];
				if (mobility_type != "") {
					list<float> vals <- [];
					loop j from: 1 to: mode_matrix.columns - 1 {
						vals << float(mode_matrix[j, i]);
					}

					charact_per_mobility[mobility_type] <- vals;
					color_per_mobility[mobility_type] <- rgb(mode_matrix[7, i]);
					width_per_mobility[mobility_type] <- float(mode_matrix[8, i]);
					speed_per_mobility[mobility_type] <- float(mode_matrix[9, i]);
				}

			}

		} else {
			matrix mode_matrix <- matrix(mode_file_city_maut);
			loop i from: 0 to: mode_matrix.rows - 1 {
				string mobility_type <- mode_matrix[0, i];
				if (mobility_type != "") {
					list<float> vals <- [];
					loop j from: 1 to: mode_matrix.columns - 1 {
						vals << float(mode_matrix[j, i]);
					}

					charact_per_mobility[mobility_type] <- vals;
					color_per_mobility[mobility_type] <- rgb(mode_matrix[7, i]);
					width_per_mobility[mobility_type] <- float(mode_matrix[8, i]);
					speed_per_mobility[mobility_type] <- float(mode_matrix[9, i]);
				}

			}

		}

	}


	action compute_graph {
		loop mobility_mode over: color_per_mobility.keys {
			graph_per_mobility[mobility_mode] <- as_edge_graph(road where (mobility_mode in each.mobility_allowed)) use_cache false;
		}

	}

	//    reflex update_road_weights
	//    {
	//   	 ask road
	//   	 {
	//   		 do update_speed_coeff;
	//   		 congestion_map[self] <- speed_coeff;
	//   	 }
	//
	//    }
	reflex update_buildings_distribution {
		buildings_distribution <- map(color_per_category.keys collect (each::0));
		ask building {
			buildings_distribution[usage] <- buildings_distribution[usage] + 1;
		}

	}

	reflex save_bug_attribute when: (false) {
		write "transport_type_cumulative_usage" + transport_type_cumulative_usage;
		save [transport_type_cumulative_usage.values[0], transport_type_cumulative_usage.values[1], transport_type_cumulative_usage.values[2], transport_type_cumulative_usage.values[3]]
		rewrite: false to: "../results/mobility.csv" type: "csv";
	}

	reflex reset_cumulative_trips {
		if (current_date.hour = 6 and current_date.minute = 0) {
			transport_type_cumulative_usage <- ["walking"::0, "bike"::0, "car"::0, "bus"::0];
		}

	}

	reflex save_cumulative_trips_per_day {
		if (current_date.hour = 23 and current_date.minute = 0) {
			transport_type_cumulative_usage_per_day <-
			["walking"::transport_type_cumulative_usage.values[0], "bike"::transport_type_cumulative_usage.values[1], "car"::transport_type_cumulative_usage.values[2], "bus"::transport_type_cumulative_usage.values[3]];
		}

	}

	//    reflex report_cumulative_trips_per_day
	//    {
	//   	 write transport_type_cumulative_usage_per_day;
	//    }

}

species map_interaction_button {
	string button_name;
	bool active;
	int type;

	aspect default {
		if (active = false) {
			draw string(button_name) color: #grey font: font("FHP Sun Office", 30, #italic);
		} else {
			draw string(button_name) color: #white font: font("FHP Sun Office", 30, #italic #bold);
		}

	}

	action all_roads_to_pedestrian {
		write congestion_map;
		ask road {
			do to_pedestrian_road_ext;
		}

		write "user_command executed";
		write congestion_map;
	}

	action all_roads_to_normal {
		write congestion_map;
		ask road {
			do to_normal_road_ext;
		}

		write "user_command executed";
		//write congestion_map;
	}

}

species trip_objective {
	building place;
	int starting_hour;
	int starting_minute;
}

species bus_stop {
	list<people> waiting_people;

	aspect default {
		draw triangle(10) color: empty(waiting_people) ? #black : #blue border: #black depth: 1;
	}

}

species bus skills: [moving] {
	list<bus_stop> stops;
	map<bus_stop, list<people>> stop_passengers;
	bus_stop my_target;

	reflex new_target when: my_target = nil {
		bus_stop firstStop <- first(stops);
		remove firstStop from: stops;
		add firstStop to: stops;
		my_target <- firstStop;
	}

	reflex r {
		do goto target: my_target.location on: graph_per_mobility["car"] speed: speed_per_mobility["bus"];
		if (location = my_target.location) {
		////////  	release some people
			ask stop_passengers[my_target] {
				location <- myself.my_target.location;
				bus_status <- 2;
			}

			stop_passengers[my_target] <- [];
			///////// 	get some people
			loop p over: my_target.waiting_people {
				bus_stop b <- bus_stop with_min_of (each distance_to (p.my_current_objective.place.location));
				add p to: stop_passengers[b];
			}

			my_target.waiting_people <- [];
			my_target <- nil;
		}

	}

	aspect bu {
		draw rectangle(40 #m, 20 #m) color: empty(stop_passengers.values accumulate (each)) ? #yellow : #red border: #black;
	}

}

grid gridHeatmaps height: 50 width: 50 {
	int pollution_level <- 0;
	rgb pollution_color <- rgb(0 + pollution_level * 10, 0, 0) update: rgb(0 + pollution_level * 10, 0, 0);

	aspect pollution {
		draw shape color: pollution_color;
	}

	reflex raz when: every(1 #hour) {
		pollution_level <- 0;
	}

}

species people skills: [moving] {
	string type;
	rgb color;
	float size <- 5 #m;
	building living_place;
	list<trip_objective> objectives;
	trip_objective my_current_objective;
	building current_place;
	string mobility_mode;
	list<string> possible_mobility_modes;
	bool has_car;
	bool has_bike;
	bus_stop closest_bus_stop;
	int bus_status <- 0;

	action create_trip_objectives {
		map<string, int> activities <- activity_data[type];
		//if (activities = nil ) or (empty(activities)) {write "my type: " + type;}
		loop act over: activities.keys {
			if (act != "") {
				list<string> parse_act <- act split_with "|";
				string act_real <- one_of(parse_act);
				list<building> possible_bds;
				if (length(act_real) = 2) and (first(act_real) = "R") {
					possible_bds <- self.living_place;
					//possible_bds <- building where ((each.usage = "R") and (each.scale = last(act_real)));
				} else if (length(act_real) = 2) and (first(act_real) = "O") {
					possible_bds <- building where ((each.usage = "O") and (each.scale = last(act_real)));
				} else {
					possible_bds <- building where (each.category = act_real);
				}

				building act_build <- one_of(possible_bds);
				if (act_build = nil) {
					write "problem with act_real: " + act_real;
				}

				do create_activity(act_real, act_build, activities[act]);
			}

		}

	}

	action create_activity (string act_name, building act_place, int act_time) {
		create trip_objective {
			name <- act_name;
			place <- act_place;
			starting_hour <- act_time;
			starting_minute <- rnd(60);
			myself.objectives << self;
		}

	}

	action choose_mobility_mode {
		list<list> cands <- mobility_mode_eval();
		map<string, list<float>> crits <- weights_map[type];
		list<float> vals;
		loop obj over: crits.keys {
			if (obj = my_current_objective.name) or ((my_current_objective.name in ["RS", "RM", "RL"]) and (obj = "R")) or ((my_current_objective.name in ["OS", "OM", "OL"]) and
			(obj = "O")) {
				vals <- crits[obj];
				break;
			}

		}

		list<map> criteria_WM;
		loop i from: 0 to: length(vals) - 1 {
			criteria_WM << ["name"::"crit" + i, "weight"::vals[i]];
		}

		int choice <- weighted_means_DM(cands, criteria_WM);
		if (choice >= 0) {
			mobility_mode <- possible_mobility_modes[choice];
		} else {
			mobility_mode <- one_of(possible_mobility_modes);
		}

		transport_type_cumulative_usage[mobility_mode] <- transport_type_cumulative_usage[mobility_mode] + 1;
		speed <- speed_per_mobility[mobility_mode];
		//    write criteria_WM;
	}

	action back_home {
		self.location <- self.living_place;
	}

	reflex home {
		if current_date.hour = rnd(0, 3) and self.location != self.living_place {
			do back_home;
			my_current_objective <- nil;
		}

	}

	//reflex at_home_chill
	//{
	//    if self.location = self.living_place
	//    {
	//   	 
	//    }
	//}
	list<list> mobility_mode_eval {
		list<list> candidates;
		loop mode over: possible_mobility_modes {
			list<float> characteristic <- charact_per_mobility[mode];
			list<float> cand;
			float distance <- 0.0;
			using topology(graph_per_mobility[mode]) {
				distance <- distance_to(location, my_current_objective.place.location);
			}

			cand << characteristic[0] + characteristic[1] * distance;
			cand << characteristic[2] #mn + distance / speed_per_mobility[mode];
			cand << characteristic[4];
			cand << characteristic[5];
			add cand to: candidates;
		}

		//normalisation
		list<float> max_values;
		loop i from: 0 to: length(candidates[0]) - 1 {
			max_values << max(candidates collect abs(float(each[i])));
		}

		loop cand over: candidates {
			loop i from: 0 to: length(cand) - 1 {
				if (max_values[i] != 0.0) {
					cand[i] <- float(cand[i]) / max_values[i];
				}

			}

		}

		return candidates;
	}

	action updatePollutionMap {
		ask gridHeatmaps overlapping (current_path.shape) {
			pollution_level <- pollution_level + 1;
		}

	}

	reflex choose_objective when: my_current_objective = nil {
	//location <- any_location_in(current_place);
		if current_date.hour != 0 and current_date.hour != 1 and current_date.hour != 2 and current_date.hour != 3 and current_date.hour != 4 and current_date.hour != 5 and
		current_date.hour != 23 and current_place != living_place {
			do wander speed: 0.002;
		}

		my_current_objective <- objectives first_with ((each.starting_hour = current_date.hour) and (current_date.minute >= each.starting_minute) and (current_place != each.place));
		if (my_current_objective != nil) {
			current_place <- nil;
			possible_mobility_modes <- ["walking"];
			if (has_car) {
				possible_mobility_modes << "car";
			}

			if (has_bike) {
				possible_mobility_modes << "bike";
			}

			possible_mobility_modes << "bus";
			do choose_mobility_mode;
		}

	}

	reflex move when: (my_current_objective != nil) and (mobility_mode != "bus") {
		if ((current_edge != nil) and (mobility_mode in ["car"])) {
			road(current_edge).current_concentration <- max([0, road(current_edge).current_concentration - 1]);
		}

		if (mobility_mode in ["car"]) {
			do goto target: my_current_objective.place.location on: graph_per_mobility[mobility_mode] move_weights: congestion_map;
		} else {
			do goto target: my_current_objective.place.location on: graph_per_mobility[mobility_mode];
		}

		if (location = my_current_objective.place.location) {
			if (mobility_mode = "car" and updatePollution = true) {
				do updatePollutionMap;
			}

			current_place <- my_current_objective.place;
			location <- any_location_in(current_place);
			my_current_objective <- nil;
			mobility_mode <- nil;
		} else {
			if ((current_edge != nil) and (mobility_mode in ["car"])) {
				road(current_edge).current_concentration <- road(current_edge).current_concentration + 1;
			}

		}

	}

	reflex move_bus when: (my_current_objective != nil) and (mobility_mode = "bus") {
		if (bus_status = 0) {
			do goto target: closest_bus_stop.location on: graph_per_mobility["walking"];
			if (location = closest_bus_stop.location) {
				add self to: closest_bus_stop.waiting_people;
				bus_status <- 1;
			}

		} else if (bus_status = 2) {
			do goto target: my_current_objective.place.location on: graph_per_mobility["walking"];
			if (location = my_current_objective.place.location) {
				current_place <- my_current_objective.place;
				closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
				location <- any_location_in(current_place);
				my_current_objective <- nil;
				mobility_mode <- nil;
				bus_status <- 0;
			}

		}

	}

	aspect default {
		if (mobility_mode = nil) {
			draw circle(size) at: location + {0, 0, (current_place != nil ? current_place.height : 0.0) + 4} color: color;
		} else {
			if (mobility_mode = "walking") {
				draw circle(size) color: color;
			} else if (mobility_mode = "bike") {
				draw triangle(size) rotate: heading + 90 color: color depth: 8;
			} else if (mobility_mode = "car") {
				draw square(size * 2) color: color;
			} } }

	aspect base {
		draw circle(size) at: location + {0, 0, (current_place != nil ? current_place.height : 0.0) + 4} color: color;
	}

	aspect layer {
		if (cycle mod 180 = 0) {
			draw sphere(size) at: {location.x, location.y, cycle * 2} color: color;
		}

	} }

species road {
	list<string> mobility_allowed;
	float capacity;
	float max_speed <- max_speed_general update: max_speed_general;
	float current_concentration;
	float speed_coeff <- 1.0;
	float timer <- 0.0 update: timer - 1;
	rgb my_color <- rgb(125, 125, 125);

	action update_speed_coeff {
		speed_coeff <- shape.perimeter / max([0.01, exp(-current_concentration / capacity)]);
	}

	aspect default {
		draw shape color: my_color width: 3;
	}

	aspect mobility {
		string max_mobility <- mobility_allowed with_max_of (width_per_mobility[each]);
		draw shape width: width_per_mobility[max_mobility] color: color_per_mobility[max_mobility];
	}

	user_command to_pedestrian_road {
		mobility_allowed <- ["walking", "bike"];
		my_color <- #cornflowerblue;
		ask world {
			do compute_graph;
		}

		timer <- 10.0;
		gui_action <- 500;
	}

	action to_pedestrian_road_ext {
		mobility_allowed <- ["walking", "bike"];
		my_color <- #cornflowerblue;
		ask world {
			do compute_graph;
		}

		timer <- 10.0;
		gui_action <- 1000;
	}

	action to_normal_road_ext {
		mobility_allowed <- ["walking", "bike", "car"];
		ask world {
			do compute_graph;
		}

		my_color <- rgb(125, 125, 125);
		timer <- 10.0;
		gui_action <- 1000;
	}

	reflex update_gui_action_chart {
		if (timer = 0) {
			gui_action <- 0;
		}

	}

}

species building {
	string usage;
	string scale;
	string category;
	rgb color <- #grey;
	int height;

	aspect default {
		draw shape color: color;
	}

	aspect depth {
		if category != "Cultural" and name != "building1" {
			draw shape color: color depth: height;
		} else {
			draw shape color: #transparent;
		}

	}

}

species externalCities parent: building {
	bool train;
	string id;
	string usage <- "R";
	string scale <- "M";
	string category <- "R";

	aspect default {
		draw circle(20) color: #black border: #white;
	}

}

experiment "Starte Szenario" type: gui {
	user_command "all roads to pedestrian" {
		write congestion_map;
		ask road {
			do to_pedestrian_road_ext;
		}

		write "user_command executed";
		write congestion_map;
	}

	user_command "all roads to normal" {
		write congestion_map;
		ask road {
			do to_normal_road_ext;
		}

		write "user_command executed";
		write congestion_map;
	}

	output {
		display map type: opengl refresh: every(1 #cycle) draw_env: false background: #black #zoom //refresh: every(#hour)
		{
			event [mouse_down] action: click_to_pedestrian_road;
			event [mouse_down] action: choose_map_interaction;
			//	event [mouse_down] action: lock_display;
			overlay position: {0.1, 0.1} size: {240 #px, 680 #px} background: #black transparency: 1.0 border: #black {
				rgb text_color <- #white;
				float y <- 60 #px;
				draw "Gebäudetyp" at: {40 #px, y} color: text_color font: font("Helvetica", 48, #bold) perspective: false;
				y <- y + 40 #px;
				loop type over: color_per_category.keys {
					draw square(12 #px) at: {20 #px, y} color: color_per_category[type] border: #white;
					draw type at: {40 #px, y + 10 #px} color: color_per_category[type] font: font("Helvetica", 18 #px, #none) perspective: false;
					y <- y + 35 #px;
				}

				y <- y + 60 #px;
				draw "Menschen" at: {40 #px, y} color: text_color font: font("Helvetica", 48, #bold) perspective: false;
				y <- y + 40 #px;
				loop type over: color_per_type.keys {
					draw square(12 #px) at: {20 #px, y} color: color_per_type[type] border: #white;
					draw type at: {40 #px, y + 10 #px} color: color_per_type[type] font: font("Helvetica", 18, #none) perspective: false;
					y <- y + 35 #px;
				}

				y <- y + 30 #px;

				//   			 draw "Mobility Mode" at: { 40 # px, 600 # px } color: text_color font: font("Helvetica", 20, # bold) perspective: false;
				//   			 map<string, rgb> list_of_existing_mobility <- map<string, rgb> (["Walking"::#gold, "Bike"::#orangered, "Car"::#maroon, "Bus"::#lightgrey]);
				//   			 y <- y + 30 # px;
				//   			 loop i from: 0 to: length(list_of_existing_mobility) - 1
				//   			 {
				//   			 // draw circle(10#px) at: { 20#px, 600#px + (i+1)*25#px } color: list_of_existing_mobility.values[i]  border: #white;
				//   				 draw list_of_existing_mobility.keys[i] at: { 40 # px, 610 # px + (i + 1) * 20 # px } color: list_of_existing_mobility.values[i] font: font("Helvetica", 18, # plain)
				//   				 perspective: false;
				//   			 }

			}

			image ebw_background;
			//species gridHeatmaps aspect: pollution;
			//species pie;
			species bus_stop;
			species bus aspect: bu;
			species building aspect: depth refresh: false;
			species road;
			species people aspect: base;
			species externalCities;
			species map_interaction_button;
			graphics "time" {
				draw string("Uhrzeit: " + current_date.hour) + ":" + string(current_date.minute) color: #darkgrey font: font("FHP Sun Office", 30, #italic) at:
				{world.shape.width * 0, world.shape.height * 0.99};
			}

			graphics "hinweis" {
				draw string("Tippe einzelne Strassen an, um sie für Autos zu sperren!") color: #cornflowerblue font: font("FHP Sun Office", 25, #none) at: {0, world.shape.height * 0.93};
			}

			//   		 overlay position: { 5, 5 } size: { 240 # px, 680 # px } background: # black transparency: 1.0 border: # black
			//   		 {
			//   			 rgb text_color <- # white;
			//   			 float y <- 30 # px;
			//   			 draw "Building Usage" at: { 40 # px, y } color: text_color font: font("Helvetica", 20, # bold) perspective: false;
			//   			 y <- y + 50 # px;
			//   			 loop type over: color_per_category.keys
			//   			 {
			//   				 draw square(10 # px) at: { 20 # px, y } color: color_per_category[type] border: # white;
			//   				 draw type at: { 40 # px, y + 4 # px } color: text_color font: font("Helvetica", 18, # plain) perspective: false;
			//   				 y <- y + 50 # px;
			//   			 }
			//
			//   			 y <- y + 30 # px;
			//   			 draw "People Type" at: { 40 # px, y } color: text_color font: font("Helvetica", 20, # bold) perspective: false;
			//   			 y <- y + 30 # px;
			//   			 loop type over: color_per_type.keys
			//   			 {
			//   				 draw square(10 # px) at: { 20 # px, y } color: color_per_type[type] border: # white;
			//   				 draw type at: { 40 # px, y + 4 # px } color: text_color font: font("Helvetica", 18, # plain) perspective: false;
			//   				 y <- y + 25 # px;
			//   			 }
			//
			//   			 y <- y + 30 # px;
			//   			 draw "Mobility Mode" at: { 40 # px, 600 # px } color: text_color font: font("Helvetica", 20, # bold) perspective: false;
			//   			 map<string, rgb> list_of_existing_mobility <- map<string, rgb> (["Walking"::# green, "Bike"::# yellow, "Car"::# red, "Bus"::# blue]);
			//   			 
			//   			 y <- y + 30 # px;
			//   			 loop i from: 0 to: length(list_of_existing_mobility) - 1
			//   			 {
			//   				 draw list_of_existing_mobility.keys[i] at: { 40 # px, 610 # px + (i + 1) * 30 # px } color: list_of_existing_mobility.values[i] font: font("Helvetica", 18, # plain)
			//   				 perspective: false;
			//   			 }
			//
			//   		 }

		}

		display chart type: opengl background: #black draw_env: false refresh: every(#minute) {
			image ebw_background_charts position: {0, 0} size: {1, 1};
			chart "Fahrten tageweise" type: pie style: ring size: {0.5, 0.8} position: {world.shape.width * (0.001), -world.shape.height * 1.1} background: #transparent color: #black
			title_font: "FHP Sun" tick_font_size: 0 {
				loop i from: 0 to: length(transport_type_cumulative_usage.keys) - 1 {
					data transport_type_cumulative_usage.keys[i] value: transport_type_cumulative_usage.values[i] color: color_per_mobility[transport_type_cumulative_usage.keys[i]];
				}

			}

			//   		 chart "People Distribution" type: pie style: ring size: { 0.5, 0.8 } position: { 0, -world.shape.height * 1.1 } background: # transparent color: # black title_font: "FHP Sun"
			//   		 tick_font_size: 0
			//   		 {
			//   			 loop i from: 0 to: length(proportion_per_type.keys) - 1
			//   			 {
			//   				 data proportion_per_type.keys[i] value: proportion_per_type.values[i] color: color_per_type[proportion_per_type.keys[i]];
			//   			 }
			//
			//   		 }
			chart "Fahrten stundenweise" type: xy size: {0.5, 0.8} position: {world.shape.width * (0.45), -world.shape.height * 1.0} background: #transparent color: #white title_font:
			"FHP Sun" tick_font_size: 0 legend_font_size: 30 title_font_size: 35 {
				loop i from: 0 to: length(transport_type_cumulative_usage.keys) - 1 {
					data transport_type_cumulative_usage.keys[i] value: transport_type_cumulative_usage.values[i] color: color_per_mobility[transport_type_cumulative_usage.keys[i]];
					data "" value: gui_action;
					data "" value: max_speed_general;
				}

			}

			graphics "Nb_Agents:" {
				draw string(sum_of(transport_type_cumulative_usage.values, each)) color: #white font: font("Helvetica", 28, #bold) at: {world.shape.width * 0.11, 0.71 * world.shape.height};
				//   			 draw string("   ?") color: # white font: font("Helvetica", 28, # bold) at: { world.shape.width * 0.11, 0.76 * world.shape.height };
				//   			 draw string("Mobilitäts-Modus: ") color: # white font: font("Helvetica", 28, # none) at: { world.shape.width * 0.62, 0.71 * world.shape.height };
				//   			 draw string("Zu Fuß") color: # gold font: font("Helvetica", 24, # none) at: { world.shape.width * 0.765, 0.71 * world.shape.height };
				//   			 draw string("Fahrrad") color: # orangered font: font("Helvetica", 24, # none) at: { world.shape.width * 0.81, 0.71 * world.shape.height };
				//   			 draw string("Auto") color: # maroon font: font("Helvetica", 24, # none) at: { world.shape.width * 0.857, 0.71 * world.shape.height };
				//   			 draw string("Bus") color: # lightgrey font: font("Helvetica", 24, # none) at: { world.shape.width * 0.888, 0.71 * world.shape.height };
			}

		}

		display chart_2 type: opengl background: #black refresh: every(#day) {
			chart "Fahrten tageweise" type: series size: {0.5, 0.8} position: {world.shape.width * (0.5), -world.shape.height * 1.8} background: #transparent color: #white title_font:
			"FHP Sun" legend_font_size: 30 title_font_size: 35 {
				loop i from: 0 to: length(transport_type_cumulative_usage_per_day.keys) - 1 {
					data transport_type_cumulative_usage_per_day.keys[i] value: transport_type_cumulative_usage_per_day.values[i] color:
					color_per_mobility[transport_type_cumulative_usage_per_day.keys[i]];
				}

			}

		}

	}

}

   		 
    




