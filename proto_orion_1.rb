area "starmap" do
  star_locations = poisson_distribution do
    x 1000
    y 1000
    radius 10
  end

  star_locations.each do |x,y|
    star_name = unique_random("star_namelist")  # Or just require getting a list of star names at once?
    location star_name do
      state("x", x)
      state("y", y)
    end
  end

  EVENTS = [ "Planet mineral upgrade", "Planet mineral downgrade", "Space monster appears" ]

  intention "Planet mineral upgrade" do
  end

  location "galactic events" do
    intentions_for_next_step do
      if float_random_from(timestep() + "occurs") > 0.1
        # A random galactic event occurs this turn
        which_side = (float_random_from(timestep() + "side") * state("num_sides")).to_i

	# Get which event number, 0 through 24
        which_event = (float_random_from(timestep() + "whichevent") * EVENTS.size).to_i
	event_name = EVENTS[which_event]
      end
    end
  end
end
