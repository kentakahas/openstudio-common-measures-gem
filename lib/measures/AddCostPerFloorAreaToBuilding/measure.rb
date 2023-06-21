# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Sustainable Energy, LLC.
# See also https://openstudio.net/license
# *******************************************************************************

# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

# see the URL below for access to C++ documentation on model objects (click on "model" in the main window to view model objects)
# http://openstudio.nrel.gov/sites/openstudio.nrel.gov/files/nv_data/cpp_documentation_it/model/html/namespaces.html

# start the measure
class AddCostPerFloorAreaToBuilding < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Add Cost per Floor Area to Building'
  end

  def description
    return 'This measure will create life cycle cost objects associated with a the building. You can set a material and installation cost, demolition cost, and O&M costs. Optionally existing cost objects already associated with building can be deleted. This measure will not affect energy use of the building.'
  end

  # human readable description of modeling approach
  def modeler_description
    return "In addition to the inputs for the cost values, a number of other inputs are exposed to specify when the cost first occurs and at what frequency it occurs in the future. This measure is intended to be used as an 'Always Run' measure to apply costs to the baseline simulation before any design alternatives manipulate it. This will allow you to show the full cost for your baseline building without having to manually cost all individual objects. You could include construction costs, land, design fees, or anything else you want.

For baseline costs, 'Years Until Costs Start' indicates the year that the capital costs first occur. For new construction this will be typically be 0 and 'Demolition Costs Occur During Initial Construction' will be 'false'. For a retrofit 'Years Until Costs Start' is between 0 and the 'Expected Life' of the object, while 'Demolition Costs Occur During Initial Construction' is true.  O&M cost and frequency can be whatever is appropriate for the component."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument to remove existing costs
    remove_costs = OpenStudio::Measure::OSArgument.makeBoolArgument('remove_costs', true)
    remove_costs.setDisplayName('Remove Existing Costs')
    remove_costs.setDefaultValue(true)
    args << remove_costs

    # make an argument for material and installation cost
    lcc_name = OpenStudio::Measure::OSArgument.makeStringArgument('lcc_name', true)
    lcc_name.setDisplayName('Name for Life Cycle Cost Object')
    lcc_name.setDefaultValue('Building - Life Cycle Costs')
    args << lcc_name

    # make an argument for material and installation cost
    material_cost_ip = OpenStudio::Measure::OSArgument.makeDoubleArgument('material_cost_ip', true)
    material_cost_ip.setDisplayName('Material and Installation Costs for Construction per Area Used')
    material_cost_ip.setUnits('$/ft^2')
    material_cost_ip.setDefaultValue(0.0)
    args << material_cost_ip

    # make an argument for demolition cost
    demolition_cost_ip = OpenStudio::Measure::OSArgument.makeDoubleArgument('demolition_cost_ip', true)
    demolition_cost_ip.setDisplayName('Demolition Costs for Construction per Area Used')
    demolition_cost_ip.setUnits('$/ft^2')
    demolition_cost_ip.setDefaultValue(0.0)
    args << demolition_cost_ip

    # make an argument for duration in years until costs start
    years_until_costs_start = OpenStudio::Measure::OSArgument.makeIntegerArgument('years_until_costs_start', true)
    years_until_costs_start.setDisplayName('Years Until Costs Start')
    years_until_costs_start.setUnits('whole years')
    years_until_costs_start.setDefaultValue(0)
    args << years_until_costs_start

    # make an argument to determine if demolition costs should be included in initial building
    demo_cost_initial_const = OpenStudio::Measure::OSArgument.makeBoolArgument('demo_cost_initial_const', true)
    demo_cost_initial_const.setDisplayName('Demolition Costs Occur During Initial Construction')
    demo_cost_initial_const.setDefaultValue(false)
    args << demo_cost_initial_const

    # make an argument for expected life
    expected_life = OpenStudio::Measure::OSArgument.makeIntegerArgument('expected_life', true)
    expected_life.setDisplayName('Expected Life')
    expected_life.setUnits('whole years')
    expected_life.setDefaultValue(20)
    args << expected_life

    # make an argument for o&m cost
    om_cost_ip = OpenStudio::Measure::OSArgument.makeDoubleArgument('om_cost_ip', true)
    om_cost_ip.setDisplayName('O & M Costs for Construction per Area Used')
    om_cost_ip.setUnits('$/ft^2')
    om_cost_ip.setDefaultValue(0.0)
    args << om_cost_ip

    # make an argument for o&m frequency
    om_frequency = OpenStudio::Measure::OSArgument.makeIntegerArgument('om_frequency', true)
    om_frequency.setDisplayName('O & M Frequency')
    om_frequency.setUnits('whole years')
    om_frequency.setDefaultValue(1)
    args << om_frequency

    # TODO: - would be nice to have argument to subtract any other costs in the project, so that the cost set here is the total cost per sqft for the project, without having to manually subtract object costed in the model. would br tricky for o&m

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    remove_costs = runner.getBoolArgumentValue('remove_costs', user_arguments)
    lcc_name = runner.getStringArgumentValue('lcc_name', user_arguments)
    material_cost_ip = runner.getDoubleArgumentValue('material_cost_ip', user_arguments)
    demolition_cost_ip = runner.getDoubleArgumentValue('demolition_cost_ip', user_arguments)
    years_until_costs_start = runner.getIntegerArgumentValue('years_until_costs_start', user_arguments)
    demo_cost_initial_const = runner.getBoolArgumentValue('demo_cost_initial_const', user_arguments)
    expected_life = runner.getIntegerArgumentValue('expected_life', user_arguments)
    om_cost_ip = runner.getDoubleArgumentValue('om_cost_ip', user_arguments)
    om_frequency = runner.getIntegerArgumentValue('om_frequency', user_arguments)

    # set flags to use later
    costs_requested = false
    costs_removed = false

    # define building
    building = model.getBuilding

    # check costs for reasonableness
    if material_cost_ip.abs + om_cost_ip.abs == 0
      runner.registerInfo('No costs were requested for the building.')
    else
      costs_requested = true
    end

    # check lifecycle arguments for reasonableness
    if (years_until_costs_start < 0) && (years_until_costs_start > expected_life)
      runner.registerError('Years until costs start should be a non-negative integer less than Expected Life.')
      return false
    end
    if (expected_life < 1) && (expected_life > 100)
      runner.registerError('Choose an integer greater than 0 and less than or equal to 100 for Expected Life.')
      return false
    end
    if om_frequency < 1
      runner.registerError('Choose an integer greater than 0 for O & M Frequency.')
      return false
    end

    # short def to make numbers pretty (converts 4125001.25641 to 4,125,001.26 or 4,125,001). The definition be called through this measure
    def neat_numbers(number, roundto = 2) # round to 0 or 2)
      if roundto == 2
        number = format '%.2f', number
      else
        number = number.round
      end
      # regex to add commas
      number.to_s.reverse.gsub(/([0-9]{3}(?=([0-9])))/, '\\1,').reverse
    end

    # reporting initial condition of model
    runner.registerInitialCondition("The Building has #{building.lifeCycleCosts.size} lifecycle cost objects.")

    # remove any component cost line items associated with the construction.
    if !building.lifeCycleCosts.empty? && (remove_costs == true)
      runner.registerInfo('Removing existing lifecycle cost objects associated with the building.')
      removed_costs = building.removeLifeCycleCosts
      costs_removed = !removed_costs.empty?
    end

    # show as not applicable if no cost requested and if no costs removed
    if (costs_requested == false) && (costs_removed == false)
      runner.registerAsNotApplicable('No new lifecycle costs objects were requested, and no costs were deleted.')
    end

    # add lifeCycleCost objects if there is a non-zero value in one of the cost arguments
    if costs_requested == true

      # converting doubles to si values from ip
      material_cost_si = OpenStudio.convert(OpenStudio::Quantity.new(material_cost_ip, OpenStudio.createUnit('1/ft^2').get), OpenStudio.createUnit('1/m^2').get).get.value
      demolition_cost_si = OpenStudio.convert(OpenStudio::Quantity.new(demolition_cost_ip, OpenStudio.createUnit('1/ft^2').get), OpenStudio.createUnit('1/m^2').get).get.value
      om_cost_si = OpenStudio.convert(OpenStudio::Quantity.new(om_cost_ip, OpenStudio.createUnit('1/ft^2').get), OpenStudio.createUnit('1/m^2').get).get.value

      # adding new cost items
      lcc_mat = OpenStudio::Model::LifeCycleCost.createLifeCycleCost("LCC_Mat - #{lcc_name}", building, material_cost_si, 'CostPerArea', 'Construction', expected_life, years_until_costs_start)
      if demo_cost_initial_const
        lcc_demo = OpenStudio::Model::LifeCycleCost.createLifeCycleCost("LCC_Demo - #{lcc_name}", building, demolition_cost_si, 'CostPerArea', 'Salvage', expected_life, years_until_costs_start)
      else
        lcc_demo = OpenStudio::Model::LifeCycleCost.createLifeCycleCost("LCC_Demo - #{lcc_name}", building, demolition_cost_si, 'CostPerArea', 'Salvage', expected_life, years_until_costs_start + expected_life)
      end
      lcc_om = OpenStudio::Model::LifeCycleCost.createLifeCycleCost("LCC_OM - #{lcc_name}", building, om_cost_si, 'CostPerArea', 'Maintenance', om_frequency, 0)

    end

    # loop through lifecycle costs getting total costs under "Construction category"
    bldg_LCCs = building.lifeCycleCosts
    bldg_total_mat_cost = 0
    bldg_LCCs.each do |bldg_LCC|
      if bldg_LCC.category == 'Construction'
        bldg_total_mat_cost += bldg_LCC.totalCost
      end
    end

    # reporting final condition of model
    if !building.lifeCycleCosts.empty?
      costed_area_ip = OpenStudio.convert(OpenStudio::Quantity.new(building.lifeCycleCosts[0].costedArea.get, OpenStudio.createUnit('m^2').get), OpenStudio.createUnit('ft^2').get).get.value
      runner.registerFinalCondition("A new lifecycle cost object was added to the building. The building has an area of #{neat_numbers(costed_area_ip, 0)} (ft^2). Material and Installation costs are $#{neat_numbers(bldg_total_mat_cost, 0)}.")
    else
      runner.registerFinalCondition('There are no lifecycle cost objects associated with the building.')
    end

    return true
  end
end

# this allows the measure to be used by the application
AddCostPerFloorAreaToBuilding.new.registerWithApplication
