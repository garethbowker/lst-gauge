-- LAAP Sim Tech Gauge

gauge_type = user_prop_add_enum("Gauge Type", "None,ASI,Fuel Tank (1),Fuel Tank (2),RPM,VSI", "None", "Please choose the gauge type")
gauge_rotation_direction = user_prop_add_enum("Gauge Direction", "Clockwise, Counter-clockwise", "Clockwise", "Which way does the gauge turn when its value is incrementing?")
gauge_requires_power = user_prop_add_boolean("Gauge Requires Power", false, "Does the gauge require bus power to function?")
gauge_power_source = user_prop_add_enum("Gauge Power Source", "Bus 1,Bus 2,Avionics", "Bus 1", "If the gauge requires power, to which power bus is it connected?")

gauge_min_value = user_prop_add_real("Minimum Value", -5000.0, 5000.0, 0.0, "Minimum value for the dial to display")
gauge_max_value = user_prop_add_real("Maximum Value", -5000.0, 5000.0, 100.0, "Maximum value for the dial to display")
gauge_max_rotation = 315

gauge_restrict_angle_to_min = user_prop_add_integer("Restrict rotation to angle (Minimum)", 0, 0, gauge_max_rotation-1, "If you don't want the gauge to rotate to its fullest, you can restrict its minimum angle here. Useful for gauges that leave the stop when powered.")
gauge_restrict_angle_to_max = user_prop_add_integer("Restrict rotation to angle (Maximum)", 1, gauge_max_rotation, gauge_max_rotation, "If you don't want the gauge to rotate to its fullest, you can restrict its maximum angle here.")

--gauge = hw_stepper_motor_add("Gauge", "4WIRE_4STEP", 720, 30, false)
gauge = hw_stepper_motor_add("Gauge", "4WIRE_4STEP", 720, 10)
gauge_backlight = hw_led_add("Backlight", 0.0)

gauge_value_subscription_index = -1
gauge_volts_subscription_index = -1

gauge_is_initialising = false
gauge_initialised = false

bus_volts = 0
avionics_bus_is_on = false

function update_bus_volts(v)
    if (gauge_volts_subscription_index == -1) then
        -- Avionics bus - take the largest voltage on all buses
        bus_volts = math.max(unpack(v))
    else
        bus_volts = v[gauge_volts_subscription_index]
    end
end

function avionics_bus_changed(state)
    avionics_bus_is_on = state
end

function calculate_gauge_value(val)
    value_range = user_prop_get(gauge_max_value) - user_prop_get(gauge_min_value)
    val = val - user_prop_get(gauge_min_value) -- (This is now 0 to value_range)
    
    v = val / value_range -- v is now 0..1
    -- Scale
    scale_down_by_factor = (user_prop_get(gauge_restrict_angle_to_max) - user_prop_get(gauge_restrict_angle_to_min)) / gauge_max_rotation
    v = v * scale_down_by_factor
    v = v + (user_prop_get(gauge_restrict_angle_to_min) / gauge_max_rotation)
    return v
end

function gauge_update(value)
    print("Gauge updating.")
    local_value = 0
    if (gauge_value == -1) then
        local_value = value -- can be over-ridden for debug
    else
        local_value = value[gauge_value_subscription_index]
    end

    if (gauge_initialised) then
        local_value = var_cap(local_value, user_prop_get(gauge_min_value), user_prop_get(gauge_max_value))
        v = 0
        if (user_prop_get(gauge_requires_power) == true) then
            if (bus_volts > 0) then
                v = calculate_gauge_value(local_value)
            end
        else
            v = calculate_gauge_value(local_value)
        end

        if (user_prop_get(gauge_rotation_direction) == "Counter-clockwise") then
            v = 1-v -- invert
        end
        print("Setting gauge value to " .. v)
        hw_stepper_motor_position(gauge, v)
    end
end


function gauge_init()

    gauge_is_initialising = true
    gauge_initialised = false

    -- Initialization starting, rotate for 3 seconds to get back to the absolute minimum value for the dial, which may be less than the set minimum rotation value
    if (gauge_rotation_direction == "Clockwise") then
        hw_stepper_motor_position(gauge, nil, "ENDLESS_CLOCKWISE")
    else
        hw_stepper_motor_position(gauge, nil, "ENDLESS_COUNTERCLOCKWISE")
    end
    timer_start(3000, gauge_post_init)
end

function gauge_post_init(c)
    if (gauge_rotation_direction == "Clockwise") then
        hw_stepper_motor_calibrate(gauge, 0.0)
        hw_stepper_motor_position(gauge, 0.0)
    else
        hw_stepper_motor_calibrate(gauge, 1.0)
        hw_stepper_motor_position(gauge, 1.0)
    end

    xpl_gauge_value_subscription_string = "x"
    xpl_gauge_value_subscription_string_type = "x"
    xpl_gauge_value_subscription_index = -1

    fs2020_gauge_value_subscription_string = "x"
    fs2020_gauge_value_subscription_string_type = "x"
    fs2020_gauge_value_subscription_index = -1

    g_type = user_prop_get(gauge_type)
    if (g_type == "None") then
        print("Gauge is set to None!")
        return nil
    elseif (g_type == "Fuel Tank (1)") then
        xpl_gauge_value_subscription_string = "sim/cockpit2/fuel/fuel_quantity"
        xpl_gauge_value_subscription_string_type = "FLOAT[8]"
        xpl_gauge_value_subscription_index = 1
        fs2020_gauge_value_subscription_string = "FUEL TANK LEFT MAIN QUANTITY"
        fs2020_gauge_value_subscription_string_type = "Gallons"
        fs2020_gauge_value_subscription_index = -1
    elseif (g_type == "Fuel Tank (2)") then
        xpl_gauge_value_subscription_string = "sim/cockpit2/fuel/fuel_quantity"
        xpl_gauge_value_subscription_string_type = "FLOAT[8]"
        xpl_gauge_value_subscription_index = 2
        fs2020_gauge_value_subscription_string = "FUEL TANK RIGHT MAIN QUANTITY"
        fs2020_gauge_value_subscription_string_type = "Gallons"
        fs2020_gauge_value_subscription_index = -1
    elseif (g_type == "ASI") then
        xpl_gauge_value_subscription_string = "sim/flightmodel/position/indicated_airspeed"
        xpl_gauge_value_subscription_string_type = "FLOAT"
        xpl_gauge_value_subscription_index = -1
        fs2020_gauge_value_subscription_string = "AIRSPEED INDICATED"
        fs2020_gauge_value_subscription_string_type = "Knots"
        fs2020_gauge_value_subscription_index = -1
    elseif (g_type == "RPM") then
        xpl_gauge_value_subscription_string = "sim/cockpit2/engine/indicators/prop_speed_rpm"
        xpl_gauge_value_subscription_string_type = "FLOAT[8]"
        xpl_gauge_value_subscription_index = -1
        fs2020_gauge_value_subscription_string = "PROP RPM:1"
        fs2020_gauge_value_subscription_string_type = "RPM"
        fs2020_gauge_value_subscription_index = -1
    elseif (g_type == "VSI") then
        xpl_gauge_value_subscription_string = "sim/cockpit2/gauges/indicators/vvi_fpm_pilot"
        xpl_gauge_value_subscription_string_type = "FLOAT"
        xpl_gauge_value_subscription_index = -1
        fs2020_gauge_value_subscription_string = "VERTICAL SPEED"
        fs2020_gauge_value_subscription_string_type = "Feet per minute"
        fs2020_gauge_value_subscription_index = -1
    else
        print("Unknown gauge type: " .. g_type)
    end

    if (user_prop_get(gauge_requires_power) == true) then
        xpl_dataref_subscribe("sim/cockpit2/electrical/bus_volts", "FLOAT[6]", update_bus_volts)
        if (user_prop_get(gauge_power_source) == "Bus 1") then
            gauge_volts_subscription_index = 1
        elseif (user_prop_get(gauge_power_source) == "Bus 2") then
            gauge_volts_subscription_index = 2
        elseif (user_prop_get(gauge_power_source) == "Avionics") then
            gauge_volts_subscription_index = -1
            xpl_dataref_subscribe("sim/cockpit2/switches/avionics_power_on", "BOOLEAN", avionics_bus_changed)
        end
    end

    xpl_dataref_subscribe(xpl_gauge_value_subscription_string, xpl_gauge_value_subscription_string_type, gauge_update)
    fs2020_variable_subscribe(fs2020_gauge_value_subscription_string, fs2020_gauge_value_subscription_string_type, gauge_update)

    gauge_is_initialising = false
    gauge_initialised = true
    print("Post-initialisation complete.")
end

function gauge_destroy()
end



function event_callback(event)
    if event == "STARTED" then
        gauge_init()
    elseif event == "CLOSING" then
        gauge_destroy()
    end
end
event_subscribe(event_callback)