%% Ball flight model and symplectic integration functions

function xNext = symplecticFlightModel(x,dt,C,g)

xNext = zeros(6,1);
xNext(4:6) = x(4:6) + dt * ballFlightModel(x(4:6),C,g);
xNext(1:3) = x(1:3) + dt * xNext(4:6);

end

function xddot = ballFlightModel(xdot,C,g)

v = sqrt(xdot(1)^2 + xdot(2)^2 + xdot(3)^2);
xddot(1) = -C * v * xdot(1);
xddot(2) = -C * v * xdot(2);
xddot(3) = g - C * v * xdot(3);

xddot = xddot(:);
end

