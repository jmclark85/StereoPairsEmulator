function [aL, aR] = splayConversion(angle)
    rad = deg2rad(angle);
    splay = rad / 2;
    aL = splay;
    aR = -splay;
end