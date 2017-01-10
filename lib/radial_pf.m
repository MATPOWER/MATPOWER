function [mpc, success, iterations] = radial_pf(casedata,mpopt)
%RADIAL_PF  Solves the power flow using a backward-forward sweep method.
%
%   [mpc, success, iterations] = radial_pf(casedata,mpopt)
%
%   Inputs:
%       casedata : either a MATPOWER case struct or a string containing
%           the name of the file with the case data
%       mpopt : MATPOWER options struct to override default options
%           can be used to specify the solution algorithm, output options
%           termination tolerances, and more.
%
%   Outputs:
%       mpc : results struct with all fields from the input MATPOWER case,
%             with solved voltages, active and reactive power flows
%             and generator active and reactive power output.
%       success : success flag, 1 = succeeded, 0 = failed
%       iterations : number of iterations
%
%  See also CASEFORMAT, LOADCASE, MPOPTION.

%% load case data
mpc = loadcase(casedata);
%% branch ordering
mpc = order_radial(mpc);
%% define named indices into bus, gen, branch matrices
define_constants;
%% define vectors needed for backward-forward sweep method
% branch and demand data
[f, t, Zb, Yb, Sd, Ysh] = ...
    deal(mpc.branch(:,F_BUS),mpc.branch(:,T_BUS), ...
         mpc.branch(:,BR_R)+1j*mpc.branch(:,BR_X),1j*mpc.branch(:,BR_B), ...
         mpc.bus(:,PD)+1j*mpc.bus(:,QD),mpc.bus(:,GS)+1j*mpc.bus(:,BS));
nl = size(mpc.branch,1);
nb = size(mpc.bus,1);
Sd  =  Sd/mpc.baseMVA;
Ysh = Ysh/mpc.baseMVA;
Ybf = Yb/2;
Ybt = Yb/2;
Yd = Ysh + (sparse(f, f, Ybf, nb, nb) + sparse(t, t, Ybt, nb, nb)) * ones(nb,1);
% generator data (other than the slack bus)
pv = mpc.gen(2:end,GEN_BUS);
Pg = mpc.gen(2:end,PG)/mpc.baseMVA;
Vg = mpc.gen(2:end,VG);
%% calculate voltages and power flows
Vslack = mpc.gen(1,VG);
switch upper(mpopt.pf.alg);
    case 'PQSUM'
        [V, Qpv, Sf, St, Sslack, iterations, success] = calc_v_pq_sum(Vslack,nb,nl,f,Zb,Ybf,Ybt,Yd,Sd,pv,Pg,Vg,mpopt);
    case 'ISUM'
        [V, Qpv, Sf, St, Sslack, iterations, success] = calc_v_i_sum(Vslack,nb,nl,f,Zb,Ybf,Ybt,Yd,Sd,pv,Pg,Vg,mpopt);
    case 'YSUM'
        [V, Qpv, Sf, St, Sslack, iterations, success] = calc_v_y_sum(Vslack,nb,nl,f,Zb,Ybf,Ybt,Yd,Sd,pv,Pg,Vg,mpopt);
end
mpc.success = success;
%% update data matrices with solution
mpc.bus(:,VM) = abs(V);
mpc.bus(:,VA) = angle(V)/pi*180;
mpc.branch(:,PF) = real(Sf)*mpc.baseMVA;
mpc.branch(:,QF) = imag(Sf)*mpc.baseMVA;
mpc.branch(:,PT) = -real(St)*mpc.baseMVA;
mpc.branch(:,QT) = -imag(St)*mpc.baseMVA;
[mpc.branch(mpc.br_reverse,PF), mpc.branch(mpc.br_reverse,PT)] = ...
    deal(mpc.branch(mpc.br_reverse,PT), mpc.branch(mpc.br_reverse,PF));
[mpc.branch(mpc.br_reverse,QF), mpc.branch(mpc.br_reverse,QT)] = ...
    deal(mpc.branch(mpc.br_reverse,QT), mpc.branch(mpc.br_reverse,QF));
mpc.gen(1,PG) = real(Sslack)*mpc.baseMVA;
mpc.gen(1,QG) = imag(Sslack)*mpc.baseMVA;
if ~isempty(pv)
    mpc.gen(2:end,QG) = Qpv*mpc.baseMVA;
end
%% reverse bus and branch ordering
mpc.bus = mpc.bus(mpc.bus_order_inv,:);
mpc.bus(:,BUS_I) = mpc.bus_order(mpc.bus(:,BUS_I));
[f, t] = deal(mpc.branch(:,F_BUS),mpc.branch(:,T_BUS));
[f(mpc.br_reverse), t(mpc.br_reverse)] =  deal(t(mpc.br_reverse), f(mpc.br_reverse));
mpc.branch(:,[F_BUS T_BUS]) = [mpc.bus_order(f) mpc.bus_order(t)];
mpc.branch = mpc.branch(mpc.branch_order_inv,:);
mpc.gen(:,GEN_BUS) = mpc.bus_order(mpc.gen(:,GEN_BUS));