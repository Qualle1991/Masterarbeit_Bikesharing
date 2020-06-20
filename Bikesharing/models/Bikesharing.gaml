/*
* Name: Bikesharing
* Author: Pascal Schwerk
* Description: Game on Luckenwalde with bikesharing, based on Game It by Grignard et al. (2018) and Eberswalde by Priebe, Szczepanska, Higi, & Schröder (eingereicht).
* Tags: bikesharing, newmobility
*/
model Bikesharing

global {

//ENVIRONMENT
	float step <- 10 #mn update: 10 #mn;
	date starting_date <- date([2020, 4, 1, 1, 0]);
	// case_study needs a folder named like the city in focus
	string case_study <- "luckenwalde";
	string EPSG <- "EPSG:25833";
	//URL for Google Forms result:
	string url <- "https://docs.google.com/spreadsheets/d/e/2PACX-1vRdj4Dvf3TyVUgbW2jF3YN7NXbrN1qUGa3XGhiiiMiARxpMXsKRyzugMY3eglHjsRLLtZPiOhbOEG1e/pub?gid=2013234065&single=true&output=csv";

	//USER INTERACTION:	
	//Choice for using Google forms instead of fixed profile_file:
	string profile_input_mode <- "Feste Profil-Datei" among: ["Feste Profil-Datei", "Google Umfrage"] parameter: "Profil Import" category: "Voreinstellung";
	string scenario <- "Ausgewogen" parameter: "Szenario: " among: ["Kein Bikesharing", "Ausgewogen", "Freefloat"] category: "Voreinstellung";
	bool planned_distribution <- true parameter: "Verteilung Stationen geplant? (sonst Anordnung zufällig) " category: "Voreinstellung";
	int nb_inhabitants <- 20000 parameter: "Anzahl der Einwohner: " category: "Voreinstellung";
	int nb_people <- 1000 parameter: "Anzahl der Personen im Experiment: " min: 100 max: 10000 step: 100 category: "Voreinstellung";
	int prop_pendler <- 25 parameter: "Anteil der zusätzlichen Einpendler (in%): " min: 0 max: 100 step: 1 category: "Voreinstellung";
	int nb_shared_bikes <- 10 parameter: "Anzahl der Leihfahrräder (pro 1000 Einwohner): " min: 0 max: 100 step: 1 category: "Voreinstellung";
	//Choice for sharing_station-creation-mode:
	bool creation_mode <- false parameter: "Stationen auf Karte hinzufügen:" category: "Interaktion";
	bool disposition_setting <- true parameter: "Nächtliche Disposition durchführen:" category: "Interaktion";

	//Shapefiles:
	string ProjectFolder <- "./../includes/City/" + case_study;
	file<geometry> buildings_shapefile <- shape_file(ProjectFolder + "/buildings.shp");
	file<geometry> external_shapefile <- shape_file(ProjectFolder + "/external_cities.shp");
	file<geometry> roads_shapefile <- shape_file(ProjectFolder + "/roads.shp");
	//file<geometry> roads_shapefile <- shape_file(ProjectFolder + "/200219 Luckenwalde highways 1437.shp");
	file<geometry> bus_shapefile <- shape_file(ProjectFolder + "/bus_stops.shp");

	//TODO: Background Map schön machen
	//file background_img <- file(GISFolder + "/background.jpg");
	file performance_chart <- file("./../includes/images/performance_chart_bg.png");
	geometry shape <- envelope(roads_shapefile);

	//ROAD SPEED LIMIT
	float max_speed_general <- 50.0;

	// MOBILITY DATA
	
	file activity_file <- file(ProjectFolder + "/profiles_and_modes/ActivityPerProfile.csv");
	file criteria_file <- file(ProjectFolder + "/profiles_and_modes/CriteriaFile.csv");
	file mode_file <- file(ProjectFolder + "/profiles_and_modes/Modes.csv");
	list<string> mobility_list <- first(columns_list(matrix(mode_file)));
	file profile_file;
	
	// Artificial Usage of Bikesharing:
	float artificial_simulation_rides_per_bike;
	float artificial_simulation_rides_absolute;
	int artificial_simulation_rides_per_30min;
	list<shared_bike> free_bikes;
	list<shared_bike> artificial_used_bikes;

	//MAPS
	map<string, rgb>
	color_per_category <- ["Restaurant"::#chocolate, "Cultural"::#darkgreen, "Park"::#green, "Shopping"::#chocolate, "HS"::#dimgrey, "O"::#dimgrey, "R"::#darkgrey];
	map<string, rgb>
	color_per_type <- ["Auspendler"::#purple, "Schueler"::#gamablue, "Arbeitnehmer"::#yellow, "Heimzentrierte"::#cornflowerblue, "Rentner"::#mediumturquoise];
	map<string, map<string, int>> activity_data;
	map<string, float> proportion_per_type;
	map<string, float> proba_bike_per_type;
	map<string, float> proba_car_per_type;
	map<string, float> proba_bikesharing_per_type;
	map<string, rgb> color_per_mobility;
	map<string, float> width_per_mobility;
	map<string, float> speed_per_mobility;
	map<string, graph> graph_per_mobility;
	graph graph_per_mobility_2;
	map<string, list<float>> charact_per_mobility;
	map<road, float> congestion_map;
	map<string, map<string, list<float>>> weights_map <- map([]);

	// INDICATOR
	map<string, int> transport_type_cumulative_usage;
	map<string, int> transport_type_cumulative_usage_per_day;
	map<string, int> alltime_transport_type_cumulative_usage;
	map<string, int> buildings_distribution;

	//TESTING-COUNTERS
	int counter_rides <- 0;
	int counter_succeeded <- 0;
	int count_missed_bike <- 0;
	int day_counter;
	list day_x_label <- [0];
	float trips_per_bike_per_day;
	float trips_per_thousand_per_day;

	init {
		write mobility_list;
	// imports for people data:
		do import_profile_file;
		do profils_data_import;
		do activity_data_import;
		do criteria_file_import;
		do characteristic_file_import;
		do evaluate_scenario;
		

		//gama.pref_display_flat_charts <- true;
		create road from: roads_shapefile with: [mobility_allowed::(string(read("mobility_a")) split_with "|")]
		{
			//mobility_allowed <- ["walking", "bike", "car", "bus", "shared_bike"];
			capacity <- shape.perimeter / 10.0;
			congestion_map[self] <- 10.0; //shape.perimeter;
		}

		// mobility_graph:
		//do compute_graph;
		graph_per_mobility_2 <- as_edge_graph(road);

		// Buildings including heigt from building level if in data, else random building level between 1 and 5:
		create building from: buildings_shapefile with:
		[usage::string(read("usage")), category::string(read("category")), level::int(read("building_l")), proba_under18::float(read("unter18_A")) / 100, proba_18to65::float(read("18bis65_A")) / 100, proba_over65::float(read("ab65_A")) / 100, proba_density::float(read("density"))]
		{
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

		//Creation of sharing_stations in dependence of scenrario and planned_distribution:
		int nb_sharing_station;
		if scenario = "Kein Bikesharing" {
			nb_shared_bikes <- 0;
			nb_sharing_station <- 0;
			remove "shared_bike" from: mobility_list;
		} else {
			file<geometry> bikesharing_shapefile <- shape_file(ProjectFolder + "/sharing_stations_" + scale_sharing_stations + ".shp");
			nb_sharing_station <- length(bikesharing_shapefile);
			if (planned_distribution = true) {
				create sharing_station number: nb_sharing_station from: bikesharing_shapefile;
			} else {
				create sharing_station number: nb_sharing_station {
					location <- one_of(road).location;
				}

			}

		}

		create externalCities from: external_shapefile with: [train::string(get("train"))];
		create bus_stop from: bus_shapefile;

		// Bus EBW
		create bus {
			stops <- list(bus_stop);
			location <- first(stops).location;
			stop_passengers <- map<bus_stop, list<people>>(stops collect (each::[]));
		}

// inital number of people created:
		create people number: nb_people {
			type <- proportion_per_type.keys[rnd_choice(proportion_per_type.values)];
			vehicle_in_use <- nil;
			has_car <- flip(proba_car_per_type[type]);
			has_bike <- flip(proba_bike_per_type[type]);
			if scenario = "Kein Bikesharing" {
				has_bikesharing <- false;
			} else {
				has_bikesharing <- flip(proba_bikesharing_per_type[type]);
			}
			do choose_living_place;
			current_place <- living_place;
			location <- any_location_in(living_place);
			color <- color_per_type[type];
			closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
			closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
			do create_activites;
		}

		//prop_pendler
		ask externalCities {
			create people number: round(prop_pendler * 0.01 * nb_people / length(externalCities)) {
			//(Ein)pendler are always Arbeitnehmer
				type <- "Arbeitnehmer";
				if myself.train = "T" {
					has_bike <- flip(proba_bike_per_type[type]);
					has_bikesharing <- flip(proba_bikesharing_per_type[type]);
					has_car <- false;
					if (has_bike = true) {
						vehicle_in_use <- "bike";
					} else {
						vehicle_in_use <- nil;
					}

				} else {
					has_car <- true;
					has_bike <- false;
					has_bikesharing <- false;
					vehicle_in_use <- "car";
				}

				living_place <- myself;
				current_place <- living_place;
				location <- any_location_in(living_place);
				color <- color_per_type[type];
				closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
				closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
				do create_activites;
			}

		}

		// shared_bikes are distributed randomly at the sharing_stations:
		create shared_bike number: round(nb_shared_bikes / 1000 * nb_inhabitants){
			location <- one_of(sharing_station).location;
			in_use <- false;
			closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
			color <- #red;
			add self to: closest_sharing_station.parked_bikes;
			
		}
		
		// Figures for charts and exports:
		transport_type_cumulative_usage <- map(mobility_list collect (each::0));
		transport_type_cumulative_usage_per_day <- map(mobility_list collect (each::0));
		alltime_transport_type_cumulative_usage <- map(mobility_list collect (each::0));
		buildings_distribution <- map(color_per_category.keys collect (each::0));
		
		// Calculation of the number of artificially simulated bikesharing rides per 30 minutes
		// depending on the number of inhabitants and simulated persons:
		
		// Rides to be simulated artificially per bike:
		artificial_simulation_rides_per_bike <- 1.8 - (length(people)/nb_inhabitants)*1.8;
		// Total number of trips to be artificially simulated:
		artificial_simulation_rides_absolute <- artificial_simulation_rides_per_bike*length(shared_bike);
		// Number of trips to be artificially simulated per half hour during rush hour (7am to 7pm):
		artificial_simulation_rides_per_30min <- round(artificial_simulation_rides_absolute/13/2);
		
		// init end:
	}

	reflex update_buildings_distribution {
		buildings_distribution <- map(color_per_category.keys collect (each::0));
		ask building {
			buildings_distribution[usage] <- buildings_distribution[usage] + 1;
		}

	}
	
	string scale_sharing_stations;
	action evaluate_scenario {
		if (scenario = "Ausgewogen") {
			scale_sharing_stations <- "mid";
		} else if (scenario = "Freefloat") {
			scale_sharing_stations <- "high";
		}

	}

	// Clicking action: Place the new sharing_station on the street next to users' location
	action create_sharing_station {
		if creation_mode = true {
			create sharing_station number: 1 {
				location <- location of (road closest_to (#user_location));
				parked_bikes <- nil;
			}

		}

	}

	//Choice of source for import of profile data:
	action import_profile_file {
		if profile_input_mode = "Feste Profil-Datei" {
			profile_file <- file(ProjectFolder + "/profiles_and_modes/Profiles.csv");
		} else if profile_input_mode = "Google Umfrage" {
			profile_file <- csv_file(url, ",");
		}

	}

	//Import profile data:
	action profils_data_import {
		matrix profile_matrix <- matrix(profile_file);
		loop i from: 0 to: profile_matrix.rows - 1 {
			string profil_type <- profile_matrix[0, i];
			if (profil_type != "") {
				proba_car_per_type[profil_type] <- float(profile_matrix[2, i]);
				proba_bike_per_type[profil_type] <- float(profile_matrix[3, i]);
				proba_bikesharing_per_type[profil_type] <- float(profile_matrix[4, i]);
				proportion_per_type[profil_type] <- float(profile_matrix[5, i]);
			}

		}

		write profile_matrix;
	}

	//Import activity data:
	action activity_data_import {
		matrix activity_matrix <- matrix(activity_file);
		loop i from: 1 to: activity_matrix.rows - 1 {
			string people_type <- activity_matrix[0, i];
			map<string, int> activities;
			string current_activity <- "";
			loop j from: 1 to: activity_matrix.columns - 1 {
				string act <- activity_matrix[j, i];
				if (act != current_activity) {
					activities[act] <- j - 1;
					current_activity <- act;
				}

			}

			activity_data[people_type] <- activities;
		}

	}

	//Import criteria data:
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

	//Import charateristics:
	action characteristic_file_import {
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

	}

	//Create graph per mobility:
	action compute_graph {
		loop mobility_mode over: color_per_mobility.keys {
			graph_per_mobility[mobility_mode] <- as_edge_graph(road where (mobility_mode in each.mobility_allowed)) use_cache false;
		}

	}

	reflex update_road_weights {
		ask road {
			do update_speed_coeff;
			congestion_map[self] <- speed_coeff;
		}

	}

	//Save cumulative usage:
	reflex save_mobility_data when: (true) {
		list<int> saveit;
		loop i from:0 to: length(transport_type_cumulative_usage)-1{
			add transport_type_cumulative_usage.values[i] to: saveit;
		}
		save saveit rewrite: false to: "../results/mobility.csv" type: "csv";
	}

	// Cumulative trips are just stored for one day:
	reflex reset_cumulative_trips {
		if (current_date.hour = 6 and current_date.minute = 0) {
			loop i from: 0 to: length(transport_type_cumulative_usage)-1{
				alltime_transport_type_cumulative_usage[alltime_transport_type_cumulative_usage.keys[i]] <- alltime_transport_type_cumulative_usage.values[i]+transport_type_cumulative_usage.values[i];
			}
			transport_type_cumulative_usage <- map(mobility_list collect (each::0));
			day_counter <- day_counter + 1;
			add day_counter to: day_x_label;
		}

	}
	

	//this reflex is responsible for the artificial utilization of bikes in case of just simulating a smaller group of the whole population of a city:
	//it runs every half an hour at daytime
	reflex artificial_utilization when: current_date.hour >6 and current_date.hour <20 and every(30#mn) and scenario != "Kein Bikesharing" and artificial_simulation_rides_per_30min>0 {
		
		// take a many bikes as the artificial simulation factor tells:
		loop i from: 0 to: artificial_simulation_rides_per_30min{
			//Collection of all bikes, not being in use at the moment:
			loop y from:0 to:length(shared_bike)-1{
				if(shared_bike[y].in_use = false){
					add shared_bike[y] to: free_bikes;
				}
			}
			//take a random bike being not in use --> put it on a collection of bikes being in artificial simulated use and set it on in_use = true: 
			add free_bikes[rnd(0,length(free_bikes)-1)] to: artificial_used_bikes;
			last(artificial_used_bikes).in_use <- true;
			remove last(artificial_used_bikes) from: last(artificial_used_bikes).closest_sharing_station.parked_bikes;
			write string(current_date.hour) + ":" + string(current_date.minute);
			write artificial_used_bikes;
		}
			
			//this part is responsible for ending the artificial utilization of bikes every 30 minutes:
			loop while:length(artificial_used_bikes)>artificial_simulation_rides_per_30min{
			add artificial_used_bikes[0] to: artificial_used_bikes[0].closest_sharing_station.parked_bikes;
			artificial_used_bikes[0].in_use <- false;
			remove artificial_used_bikes[0] from: artificial_used_bikes;
			write string(current_date.hour) + ":" + string(current_date.minute);
			write artificial_used_bikes;
		}
	} 

	// Save cumulated numbers every evening for the daily charts: 
	reflex save_cumulative_trips_per_day {
		if (current_date.hour = 23 and current_date.minute = 0) {
			loop i from: 0 to: length(mobility_list)-1{
			add mobility_list[i]::transport_type_cumulative_usage.values[i] to:transport_type_cumulative_usage_per_day;	
			}
		}

	}
	
	
	reflex calculate_sharing_usage when: (current_date.hour = 0 and current_date.minute = 0 and scenario != "Kein Bikesharing")  {
		int y;
		loop i from: 0 to: length(shared_bike) - 1 {
			y <- y + shared_bike[i].usage_counter;
		}
		if (day_counter > 0) {
			//trips_per_bike_per_day <- round((y / (nb_shared_bikes*(1000/length(people))) / day_counter));
			trips_per_bike_per_day <- with_precision((y / (length(shared_bike)) / day_counter),1);
			trips_per_thousand_per_day <- with_precision((y * (1000 /length(people)) / day_counter),1);
		}
		
		//global end:
	}

	//DEFINITION OF DIFFERENT SPECIES:
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

		// Everytime the bus stopped at a target, it will get a new target:
		reflex new_target when: my_target = nil {
			bus_stop firstStop <- first(stops);
			remove firstStop from: stops;
			add firstStop to: stops;
			my_target <- firstStop;
		}

		// Bus ride routine:
		reflex ride {
		//do goto target: my_target.location on: graph_per_mobility["car"] speed: speed_per_mobility["bus"];
			do goto target: my_target.location speed: speed_per_mobility["bus"];
			//do goto target: my_target.location on: graph_per_mobility_2 speed: speed_per_mobility["bus"];
			if (location = my_target.location) {
			//release people according to stop_passengers list:
				ask stop_passengers[my_target] {
					location <- myself.my_target.location;
					bus_status <- 2;
				}

				stop_passengers[my_target] <- [];
				//get waiting people:
				loop p over: my_target.waiting_people {
					bus_stop b <- bus_stop with_min_of (each distance_to (p.my_current_objective.place.location));
					add p to: stop_passengers[b];
				}

				my_target.waiting_people <- [];
				my_target <- nil;
			}

		}

		aspect default {
			draw rectangle(40 #m, 20 #m) color: empty(stop_passengers.values accumulate (each)) ? #yellow : #red border: #black;
		}

	}

	species sharing_station {
	//sharing_stations have a list of parked_bikes:
		list<shared_bike> parked_bikes;
		//The height shows how many shared_bikes are parked at the sharing_station:
		float height <- 50.0 update: 50.0 + 50.0 * length(parked_bikes);
		//For bike collection and disposition:
		list<shared_bike> collector;
		list<sharing_station> sorted_stations;
		//TODO: Zähler für Nutzung

		// collect bikes that are too much:
		action collect_bikes {
			int count_bikes <- length(shared_bike);
			int count_sharing_stations <- length(sharing_station);
			if (length(parked_bikes) > (count_bikes / count_sharing_stations)) {
				loop i from: 0 to: (length(parked_bikes) - count_bikes / count_sharing_stations) - 1 {
					add last(parked_bikes) to: collector;
					remove last(parked_bikes) from: parked_bikes;
				}

			}

			sorted_stations <- sort_by(list(sharing_station), length(each.parked_bikes));
		}
		//Distribute bikes to the sharing_stations with lessest count of shared_bikes:
		action distribute_bikes {
			if (length(collector) > 0) {
				loop i from: 0 to: length(collector) - 1 {
					add last(collector) to: first(sorted_stations).parked_bikes;
					last(first(sorted_stations).parked_bikes).closest_sharing_station <- first(sorted_stations);
					remove last(collector) from: collector;
					sorted_stations <- sort_by(list(sharing_station), length(each.parked_bikes));
				}

			}

		}

		// Distribute bicycles evenly among stations at fixed times:
		
		reflex disposition when: current_date.hour = rnd(3, 7) {
			if(disposition_setting = true){
			do collect_bikes;
			do distribute_bikes;
			}
		}

		aspect default {
			draw hexagon(10, 10) color: empty(parked_bikes) ? #white : #red border: #red depth: height;
		}

	}

	species shared_bike {
	//locaion of shared_bike is defined by the closest sharing_station:
		sharing_station closest_sharing_station;
		rgb color;
		float size <- 5 #m;
		bool in_use;
		int usage_counter;

		aspect default {
			draw circle(size) color: color;
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
		bus_stop closest_bus_stop;
		sharing_station closest_sharing_station;
		bool has_car;
		bool has_bike;
		bool has_bikesharing;
		string vehicle_in_use;
		list<string> possible_mobility_modes;
		string mobility_mode;
		int bus_status <- 0;
		int shared_bike_status <- 0;
		shared_bike current_shared_bike <- nil;
		list<string> latest_modes;

		action create_activites {
			map<string, int> activities <- activity_data[type];
			//if (activities = nil ) or (empty(activities)) {write "my type: " + type;}
			loop act over: activities.keys {
				if (act != "") {
					list<string> parse_act <- act split_with "|";
					string act_real <- one_of(parse_act);
					list<building> possible_bds;
					list<externalCities> possible_ec;
					// "Auspendler" are going to externalCities:
					if (act_real = "E" and has_car = true) { //with parameter train = F if they have a car
						possible_bds <- externalCities where (each.train = "F");
					} else if (act_real = "E" and has_car = false) { //with parameter train = T if they have no car --> they will take the train in the end:
						possible_bds <- externalCities where (each.train = "T");
					} else {
						possible_bds <- building where (each.category = act_real);
					}

					building act_build <- one_of(possible_bds);
					if (act_build = nil) {
						write "problem with act_real: " + act_real;
					}

					do create_trip_objectives(act_real, act_build, activities[act]);
				} } }

		action choose_living_place {
			list<building> possible_living_bds;
			if (type = "Rentner") {
				possible_living_bds <- building where ((each.usage = "R") and (flip(each.proba_over65)) and (flip(each.proba_density)));
			} else if (type = "Schueler") {
				possible_living_bds <- building where ((each.usage = "R") and (flip(each.proba_under18)) and (flip(each.proba_density)));
			} else {
				possible_living_bds <- building where ((each.usage = "R") and (flip(each.proba_18to65)) and (flip(each.proba_density)));
			}

			living_place <- one_of(possible_living_bds);
		}

		action create_trip_objectives (string act_name, building act_place, int act_time) {
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
				if (obj = my_current_objective.name) or ((my_current_objective.name = "R") and (obj = "R")) or ((my_current_objective.name = "O") and
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
		}

		action back_home {
			self.location <- any_location_in(self.living_place);
			current_place <- living_place;
			vehicle_in_use <- nil;
			my_current_objective <- nil;
			mobility_mode <- nil;
		}

		//Sometimes it happens that people do not get back home independently, this is to reset peoples' location to home again:
		reflex home when: current_date.hour = rnd(1, 3) and self.current_place != self.living_place and bus_status = 0 {
			do back_home;
		}

		//Evaluation of mobility_modes:
		list<list> mobility_mode_eval {
			list<list> candidates;
			loop mode over: possible_mobility_modes {
				list<float> characteristic <- charact_per_mobility[mode];
				list<float> cand;
				float distance <- 0.0;
				distance <- distance_to(location, my_current_objective.place.location);
				//using topology(graph_per_mobility[mode]) {
				using topology(graph_per_mobility_2) {
					//distance <- distance_to(location, my_current_objective.place.location);
				}

				cand << characteristic[0] + characteristic[1] * distance;
				cand << characteristic[2] #mn + distance / speed_per_mobility[mode];
				cand << characteristic[4];
				cand << characteristic[5];
				add cand to: candidates;
			}

			//normalisation:
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

		//Choosing the means of transport:
		reflex choose_objective when: my_current_objective = nil {
		//Person is moving around if not sleeping and not home:
			if current_date.hour != 0 and current_date.hour != 1 and current_date.hour != 2 and current_date.hour != 3 and current_date.hour != 4 and current_date.hour != 5 and
			current_date.hour != 23 and current_place != living_place {
				do wander speed: 0.002;
			}

			//Set current objective and possible mobility_modes:
			my_current_objective <- objectives first_with ((each.starting_hour = current_date.hour) and (current_date.minute >= each.starting_minute) and (current_place != each.place));
			if (my_current_objective != nil) {
				possible_mobility_modes <- nil;
				if (vehicle_in_use = nil) {
					possible_mobility_modes << "walking";
					possible_mobility_modes << "bus";
					//Shared bike has to be available: 
					if(scenario != "Kein Bikesharing"){
						if (has_bikesharing and length(self.closest_sharing_station.parked_bikes) > 0) {
							possible_mobility_modes << "shared_bike";
						}
					}

				}
				//The car has to be with the person:
				if (has_car and vehicle_in_use = "car") or (has_car and current_place = living_place) {
					possible_mobility_modes << "car";
				}
				//The bike has to be with the person:
				if (has_bike and vehicle_in_use = "bike") or (has_bike and current_place = living_place) {
					possible_mobility_modes << "bike";
				}
				//current_place <- nil;
				do choose_mobility_mode;
			}

		}

		//Move according to the selected mobility mode (bus and shared_bike are seperated):
		reflex move when: (my_current_objective != nil) and (mobility_mode != "bus") and (mobility_mode != "shared_bike") {
		/*
		if ((current_edge != nil) and (mobility_mode in ["car"])) {
			road(current_edge).current_concentration <- max([0, road(current_edge).current_concentration - 1]);
		}
 */
			if (mobility_mode in ["car"]) {
			//do goto target:(road with_min_of (each distance_to (self)));
			//do goto target: my_current_objective.place.location on: graph_per_mobility[mobility_mode] move_weights: congestion_map;
				do goto target: my_current_objective.place.location move_weights: congestion_map;
				//do goto target: my_current_objective.place.location on: graph_per_mobility_2 move_weights: congestion_map;
				counter_rides <- counter_rides + 1;
			} else {
			//do goto target:(road with_min_of (each distance_to (self)));
			//do goto target: my_current_objective.place.location on: graph_per_mobility[mobility_mode];
				do goto target: my_current_objective.place.location;
				//do goto target: my_current_objective.place.location on: graph_per_mobility_2;
				counter_rides <- counter_rides + 1;
			}

			if (self.location = my_current_objective.place.location) {
				current_place <- my_current_objective.place;
				location <- any_location_in(current_place);
				my_current_objective <- nil;
				closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
				closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
				if (mobility_mode in ["car", "bike"]) {
					vehicle_in_use <- mobility_mode;
				}

				add mobility_mode to: latest_modes;
				mobility_mode <- nil;
				counter_succeeded <- counter_succeeded + 1;
			}
			/*
		  
		  else { //TODO: What is happening here?
			if ((current_edge != nil) and (mobility_mode in ["car"])) {
				road(current_edge).current_concentration <- road(current_edge).current_concentration + 1;
			}

		}
		
		*/
		}

		//Move according to the selected mobility mode bus:
		reflex move_bus when: (my_current_objective != nil) and (mobility_mode = "bus") {
		//Person has to go to the bus_stop:
			if (bus_status = 0) {
			//do goto target:(road with_min_of (each distance_to (self)));
			//do goto target: closest_bus_stop.location on: graph_per_mobility["walking"];
				do goto target: closest_bus_stop.location;
				//do goto target: closest_bus_stop.location on: graph_per_mobility_2;
				counter_rides <- counter_rides + 1;
				if (location = closest_bus_stop.location) {
					add self to: closest_bus_stop.waiting_people;
					bus_status <- 1;
				}

			} else if (bus_status = 2) { //Person has arrived at the desired bus_stop and walks the last piece to the destination
			//do goto target:(road with_min_of (each distance_to (self)));
			//do goto target: my_current_objective.place.location on: graph_per_mobility["walking"];
				do goto target: my_current_objective.place.location;
				//do goto target: my_current_objective.place.location on: graph_per_mobility_2;
				//Person has arrived finally:
				if (location = my_current_objective.place.location) {
					current_place <- my_current_objective.place;
					location <- any_location_in(current_place);
					my_current_objective <- nil;
					closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
					closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
					add mobility_mode to: latest_modes;
					mobility_mode <- nil;
					bus_status <- 0;
					counter_succeeded <- counter_succeeded + 1;
				}

			}

		}

		//Move according to the selected mobility mode shared_bike:	
		reflex move_shared_bike when: (my_current_objective != nil) and (mobility_mode = "shared_bike") {
		//Not yet started riding the shared_bike --> go to closest sharing_station:
			if (shared_bike_status = 0) {
			//do goto target:(road with_min_of (each distance_to (self)));
			//do goto target: closest_sharing_station.location on: graph_per_mobility["walking"];
				do goto target: closest_sharing_station.location;
				//do goto target: closest_sharing_station.location on: graph_per_mobility_2;
				//Person has found a bike and takes it to the sharing_station next to the target:
				if (location = closest_sharing_station.location and length(self.closest_sharing_station.parked_bikes) > 0) {
					if(closest_sharing_station.parked_bikes[0].in_use = false){
						shared_bike_status <- 1;
						current_shared_bike <- closest_sharing_station.parked_bikes[0];
						current_shared_bike.in_use <- true;
						current_shared_bike.usage_counter <- current_shared_bike.usage_counter + 1;
						remove closest_sharing_station.parked_bikes[0] from: closest_sharing_station.parked_bikes;
						//do goto target:(road with_min_of (each distance_to (self)));
						//do goto target: sharing_station with_min_of (each distance_to (my_current_objective)) on: graph_per_mobility["shared_bike"];
						do goto target: sharing_station with_min_of (each distance_to (my_current_objective));
						//do goto target: sharing_station with_min_of (each distance_to (my_current_objective)) on: graph_per_mobility_2;
						counter_rides <- counter_rides + 1;
					}
					else{
						write "Alle Fahrräder sind in Benutzung";
					}
				}
				// If a person arrives at the sharing_station and someone else took the last shared_bike before:
				if (location = closest_sharing_station.location and length(self.closest_sharing_station.parked_bikes) = 0) {
					write "Mhh, kein Fahrrad mehr da :(";
					count_missed_bike <- count_missed_bike + 1;
					do choose_mobility_mode;
				}

				//Person arrives at the sharing_station next to the final destination:
				if (location = (sharing_station with_min_of (each distance_to (my_current_objective))).location) {
					closest_sharing_station <- sharing_station with_min_of (each distance_to (my_current_objective));
					add current_shared_bike to: closest_sharing_station.parked_bikes;
					current_shared_bike.closest_sharing_station <- closest_sharing_station;
					current_shared_bike.in_use <- false;

					//do goto target:(road with_min_of (each distance_to (self)));
					//do goto target: my_current_objective.place.location on: graph_per_mobility["walking"];
					do goto target: my_current_objective.place.location;
					//do goto target: my_current_objective.place.location on: graph_per_mobility_2;
				}

				//Person finally arrived:
				if (location = my_current_objective.place.location) {
					current_place <- my_current_objective.place;
					location <- any_location_in(current_place);
					my_current_objective <- nil;
					closest_bus_stop <- bus_stop with_min_of (each distance_to (self));
					closest_sharing_station <- sharing_station with_min_of (each distance_to (self));
					add mobility_mode to: latest_modes;
					mobility_mode <- nil;
					shared_bike_status <- 0;
					current_shared_bike <- nil;
					counter_succeeded <- counter_succeeded + 1;
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

	}

	species building {
		string usage;
		string category;
		float proba_under18;
		float proba_18to65;
		float proba_over65;
		float proba_density;
		rgb color <- #grey;
		int level;
		float height;

		aspect default {
			draw shape color: color depth: height;
		}

	}

	species externalCities parent: building {
		string train;
		string id;
		string usage <- "R";
		string category <- "R";

		aspect default {
			draw circle(20) color: #black border: #white;
		}

	} }


experiment "Starte Szenario" type: gui { //TODO: Layout map and charts
	output {
	//monitor test value: current_date.hour refresh: every(1#minute);
		display map type: opengl refresh: every(1 #cycle) draw_env: false background: #black //refresh: every(#hour)
		{
			event [mouse_down] action: create_sharing_station;
			
			overlay position: { 5, 5 } size: { 240 # px, 680 # px } background: # black transparency: 1.0 border: # black
			{
				rgb text_color <- # white;
				float y <- 60 # px;
				draw "Gebäudetypen:" at: { 40 # px, y } color: text_color font: font("Helvetica", 48, # bold) perspective: false;
				y <- y + 40 # px;
				loop type over: color_per_category.keys
				{
					draw square(12 # px) at: { 20 # px, y } color: color_per_category[type] border: # white;
					draw type at: { 40 # px, y + 10 # px } color: color_per_category[type] font: font("Helvetica", 18 , # none) perspective: false;
					y <- y + 35 # px;
				}

				y <- y + 60 # px;
				draw "Mobilitätstypen:" at: { 40 # px, y } color: text_color font: font("Helvetica", 48, # bold) perspective: false;
				y <- y + 40 # px;
				loop type over: color_per_type.keys
				{
					draw square(12 # px) at: { 20 # px, y } color: color_per_type[type] border: # white;
					draw type at: { 40 # px, y + 10 # px } color: color_per_type[type] font: font("Helvetica", 18, # none) perspective: false;
					y <- y + 35 # px;
				}

				y <- y + 30 # px;
				
				if(scenario != "Kein Bikesharing")
				{ 
					draw ("Use per Bike per Day: " + trips_per_bike_per_day) at: {world.shape.width * 0.05, world.shape.height * 0.94} color: (trips_per_bike_per_day < 4) ? #red : #green;
					draw ("Average usage per 1000 People: " + trips_per_thousand_per_day) at: {world.shape.width * 0.05, world.shape.height * 0.96} color: (trips_per_thousand_per_day < 30) ? #red : #green;
				}
				draw ("Fahrten angetreten: " + counter_rides) at: {world.shape.width * 0.05, world.shape.height * 0.98} color: #white;
				draw ("Fahrten beendet: " + counter_succeeded) at: {world.shape.width * 0.05, world.shape.height * 1} color: #white;
				draw ("Uhrzeit: " + current_date.hour) + ":" + (current_date.minute) at: {world.shape.width * 1.1, world.shape.height * 0.05} color: #darkgrey font: font("Arial", 30, #italic);

			}
			

/*
			image background_img;
			*/
			species building aspect: default; // refresh: false;
			species road;
			species externalCities;
			species bus_stop;
			species sharing_station;
			species shared_bike;
			species bus aspect: default;
			species people aspect: default;

/*
			chart "People Distribution" type: pie style: ring size: {0.5, 0.5} position: {1, 0} background: #black color: #black title_font: "Arial" {
				loop i from: 0 to: length(proportion_per_type.keys) - 1 {
					data proportion_per_type.keys[i] value: proportion_per_type.values[i] color: color_per_type[proportion_per_type.keys[i]];
				}

			} */
		
		}

		display Live_Usage type: java2D background: #black draw_env: false refresh: every(6 #cycle) {


			chart "Verteilung Verkehrtypen pro Stunde (kumuliert pro Tag)" type: series position: {0, 0} size: {1, 0.5} background: #black color: #white title_font: "Arial" {
				loop i from: 0 to: length(transport_type_cumulative_usage.keys) - 1 {
					data transport_type_cumulative_usage.keys[i] value: transport_type_cumulative_usage.values[i] color: color_per_mobility[transport_type_cumulative_usage.keys[i]];
				}

			}
			
				chart "Verlauf: Nutzung Bikesharing pro Stunde (kumuliert pro Tag)" type: series position: {0, 0.5} size: {1, 0.5} background: #black color: #white title_font: "Arial" {
					data "shared_bike" value: transport_type_cumulative_usage["shared_bike"] color: color_per_mobility["shared_bike"];
				}
			}

		display Usage_per_Day type: java2D background: #black refresh: every(#day) {
						chart "Verlauf: Verteilung Verkehrtypen pro Tag" type: series position: {0, 0.5} size: {1, 0.5} x_serie_labels: day_x_label background: #black color: #white title_font: "Arial" {
				loop i from: 0 to: length(transport_type_cumulative_usage_per_day.keys) - 1 {
					data transport_type_cumulative_usage.keys[i] value: transport_type_cumulative_usage.values[i] color:
					color_per_mobility[transport_type_cumulative_usage.keys[i]];
				}

			}
						chart "Verteilung Verkehrtypen letzter Tag" type: pie style: ring position: {0.25, 0} size: {0.5, 0.5} background: #black color: #white title_font: "Arial" {
				loop i from: 0 to: length(transport_type_cumulative_usage.keys) - 1 {
					data transport_type_cumulative_usage.keys[i] value: round(transport_type_cumulative_usage.values[i]) color: color_per_mobility[transport_type_cumulative_usage.keys[i]];
				}

			}

		}
		
		

		display Performance background: #white refresh: every(#day) {
			chart "Bike Share System Performance" tick_font: "Arial" legend_font: "Arial" label_font: "Arial" title_font: "Arial" color: #black background: #white type: xy x_tick_unit: 1.0
			y_tick_unit: 10.0 x_range: [0, 9] y_range: [0, 70] style: dot x_label: "Trips per bike (Infrastructure usage)" y_label: "Trips per 1000 people (Market Penetration)" {
				data 'Bikeusage' value: {trips_per_bike_per_day, trips_per_thousand_per_day} color: #black;
			}

			image performance_chart transparency: 0.5;
		}

	}

}

//The following experiment is a batch exploration of different amounts of bikes per 1000 inhabitants.
//The experiment runs for 7 simulated days and will be repeated 5 times each.
//The results for trips_per_thousand_per_day and trips_per_bike_per_day are the mean of the results of all repetitions.
//The results of all runs are saved in a csv-file
experiment batch_experiment_number_bikes type: batch repeat: 5 keep_seed: false until: (cycle > 1008) skills: [SQLSKILL] {
       
	parameter 'Anzahl der Leihfahrräder (pro 1000 Einwohner): ' var: nb_shared_bikes among: [ 5 , 10 , 20 ] unit: 'rate every cycle (1.0 means 100%)';
    reflex end_of_runs {
		save [day_counter, nb_shared_bikes, (simulations mean_of each.trips_per_thousand_per_day), (simulations mean_of each.trips_per_bike_per_day)] rewrite: false to: (getCurrentDateTime('yyyy-MM-dd')+"_result_batch_experiment_number_bikes.csv") type: "csv";
    }
    
    permanent {
    display Performance background: #white refresh: every(1#cycle) {
			chart "Bike Share System Performance" tick_font: "Arial" legend_font: "Arial" label_font: "Arial" title_font: "Arial" color: #black background: #white type: xy x_tick_unit: 1.0
			y_tick_unit: 10.0 x_range: [0, 9] y_range: [0, 70] style: dot x_label: "Trips per bike (Infrastructure usage)" y_label: "Trips per 1000 people (Market Penetration)" {
				data 'Bikeusage' value: {trips_per_bike_per_day, trips_per_thousand_per_day} color: #black;
			}
		}
	}
}


experiment batch_experiment_nobs_vs_bs type: batch repeat: 2 keep_seed: false until: (cycle > 504) skills: [SQLSKILL] {
       
	parameter 'Szenario: ' var: scenario among: [ "Kein Bikesharing", "Ausgewogen"] unit: 'rate every cycle (1.0 means 100%)';
    reflex end_of_runs {
    	map<string,float> mean_mode_usage;
    	loop i from:0 to: length(alltime_transport_type_cumulative_usage)-1{
    		add (alltime_transport_type_cumulative_usage.keys[i]::((simulations mean_of alltime_transport_type_cumulative_usage.values[i]))/day_counter) to:mean_mode_usage;
    	}
    	
		save [day_counter, scenario, mean_mode_usage] rewrite: false to: (getCurrentDateTime('yyyy-MM-dd')+"_result_batch_experiment_nobs_vs_bs.csv") type: "csv";
    }
}

