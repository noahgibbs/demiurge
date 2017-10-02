area "ghost ship" do
  tmx_location "outside the ship" do
    tile_layout "ghost_ship.tmx"
    description "Outside the Ship"
    state.bats = 0

    every_X_ticks("bat swarm", 5) do
      if state.bats == 0
        action description: "A huge swarm of bats flies toward the ship from some nearby hiding place. It churns around you, making it hard to see or hear."
        state.bats = 1
      else
        action description: "The bat swarm that had obscured the deck of the ship flies off, surprising you with sudden silence."
        state.bats = 0
      end
    end
  end

end
