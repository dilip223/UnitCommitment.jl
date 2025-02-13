# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function _add_system_wide_eqs!(model::JuMP.Model)::Nothing
    _add_net_injection_eqs!(model)
    _add_spinning_reserve_eqs!(model)
    _add_flexiramp_reserve_eqs!(model)
    return
end

function _add_net_injection_eqs!(model::JuMP.Model)::Nothing
    T = model[:instance].time
    net_injection = _init(model, :net_injection)
    eq_net_injection = _init(model, :eq_net_injection)
    eq_power_balance = _init(model, :eq_power_balance)
    for t in 1:T, b in model[:instance].buses
        n = net_injection[b.name, t] = @variable(model)
        eq_net_injection[b.name, t] =
            @constraint(model, -n + model[:expr_net_injection][b.name, t] == 0)
    end
    for t in 1:T
        eq_power_balance[t] = @constraint(
            model,
            sum(net_injection[b.name, t] for b in model[:instance].buses) == 0
        )
    end
    return
end

function _add_spinning_reserve_eqs!(model::JuMP.Model)::Nothing
    instance = model[:instance]
    eq_min_spinning_reserve = _init(model, :eq_min_spinning_reserve)
    for r in instance.reserves
        r.type == "spinning" || continue
        for t in 1:instance.time
            # Equation (68) in Kneuven et al. (2020)
            # As in Morales-España et al. (2013a)
            # Akin to the alternative formulation with max_power_avail
            # from Carrión and Arroyo (2006) and Ostrowski et al. (2012)
            eq_min_spinning_reserve[r.name, t] = @constraint(
                model,
                sum(model[:reserve][r.name, g.name, t] for g in r.units) +
                model[:reserve_shortfall][r.name, t] >= r.amount[t]
            )

            # Account for shortfall contribution to objective
            if r.shortfall_penalty >= 0
                add_to_expression!(
                    model[:obj],
                    r.shortfall_penalty,
                    model[:reserve_shortfall][r.name, t],
                )
            end
        end
    end
    return
end

function _add_flexiramp_reserve_eqs!(model::JuMP.Model)::Nothing
    # Note: The flexpramp requirements in Wang & Hobbs (2016) are imposed as hard constraints 
    #       through Eq. (17) and Eq. (18). The constraints eq_min_upflexiramp and eq_min_dwflexiramp 
    #       provided below are modified versions of Eq. (17) and Eq. (18), respectively, in that   
    #       they include slack variables for flexiramp shortfall, which are penalized in the
    #       objective function.
    eq_min_upflexiramp = _init(model, :eq_min_upflexiramp)
    eq_min_dwflexiramp = _init(model, :eq_min_dwflexiramp)
    instance = model[:instance]
    for r in instance.reserves
        r.type == "flexiramp" || continue
        for t in 1:instance.time
            # Eq. (17) in Wang & Hobbs (2016)
            eq_min_upflexiramp[r.name, t] = @constraint(
                model,
                sum(model[:upflexiramp][r.name, g.name, t] for g in r.units) + model[:upflexiramp_shortfall][r.name, t] >= r.amount[t]
            )
            # Eq. (18) in Wang & Hobbs (2016)
            eq_min_dwflexiramp[r.name, t] = @constraint(
                model,
                sum(model[:dwflexiramp][r.name, g.name, t] for g in r.units) + model[:dwflexiramp_shortfall][r.name, t] >= r.amount[t]
            )

            # Account for flexiramp shortfall contribution to objective
            if r.shortfall_penalty >= 0
                add_to_expression!(
                    model[:obj],
                    r.shortfall_penalty,
                    (
                        model[:upflexiramp_shortfall][r.name, t] +
                        model[:dwflexiramp_shortfall][r.name, t]
                    ),
                )
            end
        end
    end
    return
end
