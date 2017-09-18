area "moss caves" do
  location "first moss cave" do
    description "This cave is dim, with smooth sides. You can see delicious moss growing inside, out of the hot sunlight."

    every_X_ticks(3) do
      increment_state("moss")
      action do
        description "The moss slowly grows longer and more lush here."
      end
    end
  end

  location "second moss cave" do
    description "A recently-opened cave here has jagged walls, and delicious-looking stubbly moss in between the cracks."

    every_X_ticks(3) do
      increment_state("moss")
      action do
        description "The moss in the cracks seems to get thicker and softer moment by moment."
      end
    end
  end
end
