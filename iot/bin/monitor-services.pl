#!/usr/bin/env perl
# Normmal started on Daily (2AM) Cron job, but can be started ad hoc for testing  

# Compute no of seconds to next Cron Job
my $day = 86400;
my $last = ($day- (time() % $day)) + 7200; $last -= $day if $last > $day;

my($z2mPID, $noderedPID);

while ($last > 0) {
    $z2mPID = qx(pgrep -G zigbee2mqtt node);
    $noderedPID = qx(pgrep -G nodered node-red);
    chomp $z2mPID; chomp $noderedPID;
#   print "Zigbee2MQTT PID: $z2mPID, NodeRED PID $noderedPID\n";

    if ($z2mPID eq '') { 
        print qx(service zigbee2mqtt restart), "\n"; next;
    } 
    if ($noderedPID eq '') {
        print qx(service nodered restart), "\n"; next;
    }	
    do {
#	print "$last left\n";
        sleep(60);
	$last -= 60;
    }   while (-d "/proc/$z2mPID") && (-d "/proc/$noderedPID") &&  ($last > 0);
}
